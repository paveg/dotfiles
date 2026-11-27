#!/usr/bin/env bash
# Check that zsh starts with the layout that docs/design.md "Shell" and "Shell
# history (atuin)" specify, with no Nix switch: a temporary HOME holds only the
# files from <home-dir> (default home/), and `env -i` starts zsh as `zsh -c`,
# `zsh -lc`, and an interactive shell fed commands on stdin. Exported variables
# are read with `printenv` from a child process, so a missing `export` fails.
# Usage: tests/shell.sh [home-dir]   Env: ZSH_BIN overrides the zsh to test.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
home_src=${1:-$repo_dir/home}
zsh_bin=${ZSH_BIN:-$(command -v zsh)}
base_path=/usr/bin:/bin:/usr/sbin:/sbin
# $ZDOTDIR/.zshenv builds the per-user Nix directory from $USERNAME, which zsh
# sets from the real user even under `env -i`.
real_user=$(id -un)

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

checks=0
failures=0

ok() { # <name>
  checks=$((checks + 1))
  echo "ok: $1"
}

fail() { # <name> <detail>
  checks=$((checks + 1))
  failures=$((failures + 1))
  echo "FAIL: $1: $2"
}

is() { # <name> <want> <got>
  if [[ $3 == "$2" ]]; then ok "$1"; else fail "$1" "want '$2', got '$3'"; fi
}

field() { # <name> <text>
  sed -n "s|^$1=||p" <<<"$2"
}

# A fresh HOME holding this repository's files plus a fake Nix user profile, so
# that a machine without Nix still has to resolve `git` from a Nix profile
# rather than from /usr/bin, and a completion from the profile's
# site-functions, under a name no system ships.
new_home() { # <name>
  local home=$work_dir/$1
  mkdir -p "$home/.nix-profile/bin" "$home/.nix-profile/share/zsh/site-functions"
  cp -R "$home_src/." "$home/"
  printf '#!/bin/sh\necho fake-nix-profile-git\n' >"$home/.nix-profile/bin/git"
  chmod +x "$home/.nix-profile/bin/git"
  printf '#compdef dots-stub-command\n' >"$home/.nix-profile/share/zsh/site-functions/_dots_stub"
  echo "$home"
}

# A stub for each command the Nix profile installs, by the list
# tests/packages.sh checks against the built profile, so an abbreviation that
# shadows one is seen on a machine without Nix. Stubs that exist are kept.
add_profile_stubs() { # <home>
  local bin=$1/.nix-profile/bin commands=() cmd
  eval "$(sed -n '/^commands=(/,/^)/p' "$repo_dir/tests/packages.sh")"
  if ((${#commands[@]} == 0)); then
    echo "no commands=( ) list in tests/packages.sh" >&2
    exit 1
  fi
  for cmd in "${commands[@]}"; do
    if [[ ! -e $bin/$cmd ]]; then
      printf '#!/bin/sh\nexit 0\n' >"$bin/$cmd"
      chmod +x "$bin/$cmd"
    fi
  done
}

# The commands `.zshrc` binds keys for. The fzf and atuin stubs print the same
# shape of init script the real ones do: fzf binds Ctrl+t, Alt+c and Ctrl+r in
# every keymap and then restores every option through `options=(...)`, which
# fails on zle in a shell without one, and atuin binds Ctrl+r to atuin-search,
# as 18.24 names it, unless it is told not to.
add_command_stubs() { # <home>
  local bin=$1/.nix-profile/bin
  printf '#!/bin/sh\nexit 0\n' >"$bin/ghq"
  cat >"$bin/fzf" <<'STUB'
#!/bin/sh
case " $* " in
*" --zsh "*) cat <<'ZSH' ;;
zmodload zsh/parameter
fzf_saved_options="options=(${(j: :)${(kv)options[@]}})"
{
fzf-file-widget() { : }
fzf-cd-widget() { : }
fzf-history-widget() { : }
zle -N fzf-file-widget
zle -N fzf-cd-widget
zle -N fzf-history-widget
for keymap in emacs vicmd viins; do
  bindkey -M $keymap '^T' fzf-file-widget
  bindkey -M $keymap '^[c' fzf-cd-widget
  bindkey -M $keymap '^R' fzf-history-widget
done
} always {
  eval $fzf_saved_options
  unset fzf_saved_options
}
ZSH
esac
STUB
  cat >"$bin/atuin" <<'STUB'
#!/bin/sh
echo '_atuin_search() { : }'
echo 'zle -N atuin-search _atuin_search'
case " $* " in
*" --disable-ctrl-r "*) ;;
*) echo "bindkey -M emacs '^r' atuin-search" ;;
esac
STUB
  chmod +x "$bin/ghq" "$bin/fzf" "$bin/atuin"
}

# `zsh -c printenv` on a libc that cannot load en_US.UTF-8 but can load
# C.UTF-8, whose codeset LC_CTYPE asks for. glibc reads locales only from
# $LOCPATH when it is set; macOS's libc has no such variable, so a sandbox
# keeps it out of the en_US.UTF-8 directory instead.
printenv_without_en_us() { # <home>
  local env=(env -i HOME="$1" TERM=dumb PATH="$base_path" LC_CTYPE=C.UTF-8)
  if [[ $(uname -s) == Darwin ]]; then
    sandbox-exec -p '(version 1)(allow default)
      (deny file-read* (subpath "/usr/share/locale/en_US.UTF-8"))' \
      "${env[@]}" "$zsh_bin" -c printenv
  else
    mkdir -p "$work_dir/locales"
    if [[ -d /usr/lib/locale/C.utf8 ]]; then
      ln -sfn /usr/lib/locale/C.utf8 "$work_dir/locales/C.utf8"
    fi
    "${env[@]}" LOCPATH="$work_dir/locales" "$zsh_bin" -c printenv
  fi
}

# A non-secret work profile and a local zsh override, with a decoy in $HOME that
# the files must not read.
add_fixtures() { # <home>
  mkdir -p "$1/.config/dots-work/env"
  echo 'export DOTS_STATIC_ENV=static-env' >"$1/.config/dots-work/env/static.env"
  echo 'DOTS_LOCAL_RC=zdotdir' >"$1/.config/zsh/.zshrc.local"
  echo 'DOTS_LOCAL_RC=home-decoy' >"$1/.zshrc.local"
}

run_zsh() { # <home> <zsh-arg>...
  local home=$1
  shift
  env -i HOME="$home" TERM=dumb PATH="$base_path" "$zsh_bin" "$@"
}

# Feed an interactive shell a block of probe commands whose output goes to a
# file, so the prompt zsh writes to stdout cannot mix into it.
write_probe() { # <script> <out-file>
  local out
  out=$(printf '%q' "$2")
  cat >"$1" <<EOF
{
  if [[ -o zle ]]; then print -r -- "ZLE=on"; else print -r -- "ZLE=off"; fi
  print -r -- "SAVEHIST=\$SAVEHIST"
  print -r -- "HISTFILE=\${HISTFILE-}"
  print -r -- "HISTSIZE=\$HISTSIZE"
  print -r -- "PROMPT=\$PROMPT"
  if [[ -o promptsubst ]]; then print -r -- "PROMPTSUBST=on"; else print -r -- "PROMPTSUBST=off"; fi
  print -r -- "KEYMAP_MAIN=\$(bindkey -lL main)"
  for option in interactivecomments autocd autopushd pushdignoredups beep histignoredups; do
    if [[ -o \$option ]]; then print -r -- "OPTION_\$option=on"; else print -r -- "OPTION_\$option=off"; fi
  done
  print -r -- "COMPLETION_STUB=\${_comps[dots-stub-command]-none}"
  print -r -- "SKIP_GLOBAL_COMPINIT=\${skip_global_compinit-}"
  ctrl_g=\$(bindkey '^g'); ctrl_g=\${ctrl_g##* }
  ctrl_r=\$(bindkey '^r'); ctrl_r=\${ctrl_r##* }
  ctrl_t=\$(bindkey '^t'); ctrl_t=\${ctrl_t##* }
  alt_c=\$(bindkey '^[c'); alt_c=\${alt_c##* }
  print -r -- "CTRL_G=\$ctrl_g"
  print -r -- "CTRL_G_TYPE=\${widgets[\$ctrl_g]-none}"
  print -r -- "CTRL_R=\$ctrl_r"
  print -r -- "CTRL_T=\$ctrl_t"
  print -r -- "ALT_C=\$alt_c"
  expanded() {
    CONTEXT=\$1 PREBUFFER=\$2 LBUFFER=\$3 RBUFFER=\$4
    dots-abbreviation-expand
    print -r -- "\$LBUFFER"
  }
  print -r -- "ABBREVIATION_GST=\$(expanded start '' gst '')"
  print -r -- "ABBREVIATION_TEXT_RIGHT=\$(expanded start '' g 'it status')"
  print -r -- "ABBREVIATION_CONTINUATION=\$(expanded cont 'echo "first'\$'\\n' gst '')"
  print -r -- "ABBREVIATION_VARED=\$(expanded vared '' g '')"
  print -r -- "ABBREVIATION_PREBUFFER=\$(expanded start 'echo "first'\$'\\n' gst '')"
  space=\$(bindkey ' '); space=\${space##* }
  enter=\$(bindkey '^m'); enter=\${enter##* }
  print -r -- "SPACE_TYPE=\${widgets[\$space]-none}"
  print -r -- "ENTER_TYPE=\${widgets[\$enter]-none}"
  print -r -- "ENTER_CLEARS_SUGGESTION=\${ZSH_AUTOSUGGEST_CLEAR_WIDGETS[(Ie)\$enter]}"
  for name in \${(k)dots_abbreviations}; do
    if (( \$+commands[\$name] || \$+builtins[\$name] )); then print -r -- "SHADOWED \$name"; fi
  done
  print -r -- "LOCAL_RC=\${DOTS_LOCAL_RC-}"
  alias | sed 's/^/ALIAS /'
  () {
    local curcontext=:complete:dots-probe: dots_probe_cache=1
    _store_cache _dots_probe_cache dots_probe_cache
  }
  print -r -- "DONE=yes"
} >$out 2>&1
exit
EOF
}

# The probe output, with everything the shell printed on the way left in <log>.
# The shell runs in $work_dir so that the prompt in <log> cannot carry words
# from the caller's working directory.
run_interactive() { # <home> <out-file> <log> [NAME=value]...
  local home=$1 out=$2 log=$3
  shift 3
  write_probe "$out.zsh" "$out"
  (cd "$work_dir" &&
    detached env -i HOME="$home" TERM=dumb PATH="$base_path" "$@" "$zsh_bin" -i \
      <"$out.zsh" >"$log" 2>&1) || true
}

# The same probe in an interactive shell on a terminal of its own, which zsh's
# zpty module gives on Linux and macOS alike, so that zle is on, as at a desk.
run_on_terminal() { # <home> <out-file> <log>
  local home=$1 out=$2 log=$3
  write_probe "$out.zsh" "$out"
  (cd "$work_dir" && "$zsh_bin" -fc '
    zmodload zsh/zpty || exit 1
    zpty probe "${(j: :)${(q)@}}" || exit 1
    while zpty -r probe line; do print -rn -- "$line"; done
    zpty -d probe' run-on-terminal \
    env -i HOME="$home" TERM=xterm-256color PATH="$base_path" \
    "$zsh_bin" -i -c "source $(printf %q "$out.zsh")" >"$log" 2>&1) || true
}

# Without a controlling terminal, as under CI or an agent: zsh turns zle on
# whenever it can open /dev/tty, even with stdin redirected.
detached() { # <command>...
  python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"
}

# Lines in a shell's output that report a failure. zsh writes these when a file
# it sources or a command it runs is missing.
error_lines() { # <file>
  grep -iE 'no such file|not found|permission denied|parse error|bad pattern|bad substitution|cannot open|can.t open|failed' "$1" || true
}

ran_and_quiet() { # <label> <out-file> <log>
  if [[ -f $2 ]] && grep -q '^DONE=yes$' "$2"; then
    ok "$1-ran"
  else
    fail "$1-ran" "no probe output; log: $(tr '\n' ' ' <"$3" | cut -c1-200)"
  fi
  # Ignore only the one line zsh prints on a runner without a tty, and only when
  # a shell with no zsh files prints it too. If home/ caused the same line, the
  # macOS leg, which has no such noise, still fails.
  is "$1-log-quiet" "" "$(error_lines "$3" | { if grep -qx "$tty_noise" "$bare_log"; then
    grep -vx "$tty_noise"; else cat; fi; } | tr '\n' ' ' || true)"
}

path_index() { # <dir> <path-value>; 0 when absent
  local i=1 entry
  local IFS=:
  for entry in $2; do
    [[ $entry == "$1" ]] && {
      echo "$i"
      return
    }
    i=$((i + 1))
  done
  echo 0
}

# The seven directories $ZDOTDIR/.zshenv puts in front of PATH, as
# "<check-name> <directory>". Their order among themselves is not specified.
path_entries() { # <home> <xdg-data-home>
  cat <<EOF
nix-profile $1/.nix-profile/bin
per-user /etc/profiles/per-user/$real_user/bin
current-system /run/current-system/sw/bin
nix-default /nix/var/nix/profiles/default/bin
local-bin $1/.local/bin
mise-shims $2/mise/shims
aqua-bin $2/aquaproj-aqua/bin
EOF
}

check_path_holds() { # <label> <path-value> <home> <xdg-data-home>
  local label=$1 value=$2 name dir
  while read -r name dir; do
    if (($(path_index "$dir" "$value") > 0)); then
      ok "$label-$name"
    else
      fail "$label-$name" "$dir is not on PATH=$value"
    fi
  done < <(path_entries "$3" "$4")
}

check_path_before_usr_bin() { # <label> <path-value> <home> <xdg-data-home>
  local label=$1 value=$2 name dir pos usr
  usr=$(path_index /usr/bin "$value")
  while read -r name dir; do
    pos=$(path_index "$dir" "$value")
    if ((pos > 0 && usr > 0 && pos < usr)); then
      ok "$label-$name-before-usr-bin"
    else
      fail "$label-$name-before-usr-bin" \
        "$dir at $pos, /usr/bin at $usr in PATH=$value"
    fi
  done < <(path_entries "$3" "$4")
}

tree_of() { # <dir>
  (cd "$1" && find . | LC_ALL=C sort)
}

home=$(new_home default)
before_tree=$(tree_of "$home")

# Exported variables, read by a child process so that a value kept as a shell
# parameter alone fails.
vars=$(run_zsh "$home" -c printenv 2>/dev/null) || true
is xdg-config-home "$home/.config" "$(field XDG_CONFIG_HOME "$vars")"
is xdg-data-home "$home/.local/share" "$(field XDG_DATA_HOME "$vars")"
is xdg-state-home "$home/.local/state" "$(field XDG_STATE_HOME "$vars")"
is xdg-cache-home "$home/.cache" "$(field XDG_CACHE_HOME "$vars")"
is zdotdir "$home/.config/zsh" "$(field ZDOTDIR "$vars")"
is atuin-home "$home/.local/share/atuin" "$(field ATUIN_HOME "$vars")"
# With ATUIN_HOME set, atuin reads $ATUIN_HOME/config.toml unless this is set.
is atuin-config-dir "$home/.config/atuin" "$(field ATUIN_CONFIG_DIR "$vars")"
is editor nvim "$(field EDITOR "$vars")"
is visual nvim "$(field VISUAL "$vars")"
is pager less "$(field PAGER "$vars")"
is manpager 'less -R' "$(field MANPAGER "$vars")"

# en_US.UTF-8 where libc can load it, and C.UTF-8 where it cannot, as on a
# stock Ubuntu, where a missing LANG makes every child process warn. `locale`
# loads a locale the same way, so it says which this host should get.
if [[ $(env -i LC_ALL=en_US.UTF-8 locale charmap 2>/dev/null) == UTF-8 ]]; then
  want_lang=en_US.UTF-8
else
  want_lang=C.UTF-8
fi
is lang-en-us-where-libc-has-it "$want_lang" "$(field LANG "$vars")"
is lang-c-utf8-when-en-us-absent C.UTF-8 \
  "$(field LANG "$(printenv_without_en_us "$home" 2>/dev/null)")"

nonlogin_path=$(run_zsh "$home" -c 'print -r -- $PATH' 2>/dev/null) || true
check_path_holds path "$nonlogin_path" "$home" "$home/.local/share"
is nonlogin-git-from-nix-profile "$home/.nix-profile/bin/git" \
  "$(run_zsh "$home" -c 'command -v git' 2>/dev/null)"

login_path=$(run_zsh "$home" -lc 'print -r -- $PATH' 2>/dev/null) || true
check_path_holds login-path "$login_path" "$home" "$home/.local/share"
# /etc/zprofile can push what .zshenv set behind the system directories (macOS's
# runs path_helper), so $ZDOTDIR/.zprofile puts the same directories back in
# front of /usr/bin.
check_path_before_usr_bin login-path "$login_path" "$home" "$home/.local/share"
is login-git-from-nix-profile "$home/.nix-profile/bin/git" \
  "$(run_zsh "$home" -lc 'command -v git' 2>/dev/null)"

# A startup file that prints breaks every consumer of `zsh -c`, and an error on
# stderr is how a missing optional file announces that it was read anyway.
is nonlogin-quiet-stdout "" "$(run_zsh "$home" -c true 2>/dev/null)"
is nonlogin-quiet-stderr "" "$(run_zsh "$home" -c true 2>&1 >/dev/null)"
is login-quiet-stdout "" "$(run_zsh "$home" -lc true 2>/dev/null)"
is login-quiet-stderr "" "$(run_zsh "$home" -lc true 2>&1 >/dev/null)"

# .zshrc is read by interactive shells only, so nothing above may have touched
# $HOME. The completion cache below is created by the interactive run.
is home-tree-unchanged-by-noninteractive "" \
  "$(LC_ALL=C comm -13 <(echo "$before_tree") <(tree_of "$home") | tr '\n' ' ')"

probe=$work_dir/interactive.vars
log=$work_dir/interactive.log
# A shell with no zsh files at all: the baseline for what the platform prints
# and defines on its own.
bare_home=$work_dir/bare
mkdir -p "$bare_home"
bare_probe=$work_dir/bare.vars
bare_log=$work_dir/bare.log
tty_noise="not interactive and can't open terminal"
run_interactive "$bare_home" "$bare_probe" "$bare_log"

run_interactive "$home" "$probe" "$log"
ran_and_quiet interactive-shell "$probe" "$log"
probe_text=$(cat "$probe" 2>/dev/null) || true
is interactive-savehist-zero 0 "$(field SAVEHIST "$probe_text")"
is interactive-histfile-unset "" "$(field HISTFILE "$probe_text")"

histsize=$(field HISTSIZE "$probe_text")
if [[ $histsize == [0-9]* ]] && ((histsize > 1)); then
  ok interactive-histsize-keeps-a-session
else
  fail interactive-histsize-keeps-a-session \
    "up-arrow needs more than one line of in-memory history, HISTSIZE=$histsize"
fi

# A plain prompt: no command substitution, and promptsubst left off so that a
# directory or branch name cannot be run as a command.
is interactive-promptsubst-off off "$(field PROMPTSUBST "$probe_text")"
case $(field PROMPT "$probe_text") in
*'$('* | *'`'*) fail interactive-prompt-without-command-substitution \
  "PROMPT=$(field PROMPT "$probe_text")" ;;
*) ok interactive-prompt-without-command-substitution ;;
esac

# zsh picks the vi keymap when EDITOR or VISUAL contains "vi", which .zshenv's
# EDITOR=nvim does, and that takes Ctrl+a, Ctrl+e and Ctrl+k away.
is interactive-keymap-emacs 'bindkey -A emacs main' "$(field KEYMAP_MAIN "$probe_text")"
for option in interactivecomments autocd autopushd pushdignoredups histignoredups; do
  is "interactive-option-$option" on "$(field "OPTION_$option" "$probe_text")"
done
is interactive-option-no-beep off "$(field OPTION_beep "$probe_text")"

# The one compinit in .zshrc sees each Nix profile's site-functions, where gh
# and the other packages put their completions. Ubuntu's /etc/zsh/zshrc runs a
# compinit of its own, dumping into $ZDOTDIR, unless skip_global_compinit is set.
is interactive-profile-completion-registered _dots_stub \
  "$(field COMPLETION_STUB "$probe_text")"
is interactive-skip-global-compinit 1 "$(field SKIP_GLOBAL_COMPINIT "$probe_text")"

# Abbreviations expand when Space or Enter runs a user widget, and, like an
# alias would, only for names that are not already a command.
is interactive-abbreviation-expands 'git status' "$(field ABBREVIATION_GST "$probe_text")"
# Only a whole command line expands: not a word with text to its right (Ctrl+a
# to fix a typo), not a line inside an open quote or a heredoc, not vared. The
# probe sets the zle parameters as a widget sees them (measured under a pty):
# CONTEXT is start at the primary prompt, cont at a continuation line, where
# PREBUFFER holds the lines before it, and vared in vared.
is interactive-abbreviation-not-with-text-right g "$(field ABBREVIATION_TEXT_RIGHT "$probe_text")"
is interactive-abbreviation-not-on-continuation gst "$(field ABBREVIATION_CONTINUATION "$probe_text")"
is interactive-abbreviation-not-in-vared g "$(field ABBREVIATION_VARED "$probe_text")"
is interactive-abbreviation-not-after-pending-lines gst "$(field ABBREVIATION_PREBUFFER "$probe_text")"
case $(field SPACE_TYPE "$probe_text") in
user:*) ok interactive-space-expands-abbreviations ;;
*) fail interactive-space-expands-abbreviations "Space runs $(field SPACE_TYPE "$probe_text")" ;;
esac
case $(field ENTER_TYPE "$probe_text") in
user:*) ok interactive-enter-expands-abbreviations ;;
*) fail interactive-enter-expands-abbreviations "Enter runs $(field ENTER_TYPE "$probe_text")" ;;
esac
# zsh-autosuggestions restores its suggestion after a widget it does not know
# accepts the line, which leaves the suggestion drawn on the accepted line.
if [[ $(field ENTER_CLEARS_SUGGESTION "$probe_text") == [1-9]* ]]; then
  ok interactive-enter-clears-suggestion
else
  fail interactive-enter-clears-suggestion "Enter's widget is not in ZSH_AUTOSUGGEST_CLEAR_WIDGETS"
fi

# "Aliases: none by default": compare with a HOME that has no zsh files at all,
# so zsh's own aliases and anything /etc adds are not counted.
is interactive-no-aliases-added "" \
  "$(LC_ALL=C comm -13 \
    <(grep '^ALIAS ' "$bare_probe" 2>/dev/null | LC_ALL=C sort) \
    <(grep '^ALIAS ' "$probe" 2>/dev/null | LC_ALL=C sort) | tr '\n' ' ')"

if [[ -d $home/.cache/zsh ]]; then
  ok cache-dir-created
else
  fail cache-dir-created "$home/.cache/zsh does not exist"
fi

is no-history-file "" "$(cd "$home" && find . -name '*zsh_history*' | LC_ALL=C sort)"

# The probe stores one completion cache entry, the way a completion function
# does, so the use-cache and cache-path zstyles decide where it lands.
is completion-cache-in-xdg-cache ./.cache/zsh/zcompcache/_dots_probe_cache \
  "$(cd "$home" && find . -name _dots_probe_cache | LC_ALL=C sort)"

stray=
for entry in $(cd "$home" && ls -A); do
  case $entry in
  .zshenv | .config | .cache | .nix-profile | .claude) ;;
  *) stray="$stray $entry" ;;
  esac
done
is home-allowlist "" "$stray"

# $HOME above only lists its top level; a stray history or completion dump also
# lands in $ZDOTDIR, so compare the whole tree too.
added=$(LC_ALL=C comm -13 <(echo "$before_tree") <(tree_of "$home") |
  grep -vE '^\./\.cache(/zsh(/.*)?)?$' || true)
is home-tree-adds-only-cache "" "$added"

# The optional files: a work profile under the fixed ~/.config path, a local zsh
# override in $ZDOTDIR, every command the Nix profile installs, and the ones
# whose key bindings .zshrc sets up.
fix_home=$(new_home fixtures)
add_profile_stubs "$fix_home"
add_command_stubs "$fix_home"
add_fixtures "$fix_home"
fix_vars=$(run_zsh "$fix_home" -c printenv 2>/dev/null) || true
is static-env-sourced static-env "$(field DOTS_STATIC_ENV "$fix_vars")"

fix_probe=$work_dir/fixtures.vars
fix_log=$work_dir/fixtures.log
run_interactive "$fix_home" "$fix_probe" "$fix_log"
ran_and_quiet fixtures-interactive-shell "$fix_probe" "$fix_log"
fix_text=$(cat "$fix_probe" 2>/dev/null) || true
is interactive-zshrc-local-from-zdotdir zdotdir "$(field LOCAL_RC "$fix_text")"
# Ctrl+g runs the repository's ghq widget (a user widget, whatever it is named).
is interactive-ctrl-g-dots-widget "user:$(field CTRL_G "$fix_text")" \
  "$(field CTRL_G_TYPE "$fix_text")"
# No abbreviation is a command on PATH, the Nix profile's included.
is interactive-abbreviations-shadow-nothing "" \
  "$(grep '^SHADOWED ' "$fix_probe" 2>/dev/null | tr '\n' ' ' || true)"

# On a terminal, Ctrl+t and Alt+c run fzf's widgets, and Ctrl+r runs the widget
# atuin's init script binds, which has to come after fzf's.
term_probe=$work_dir/terminal.vars
term_log=$work_dir/terminal.log
run_on_terminal "$fix_home" "$term_probe" "$term_log"
term_text=$(cat "$term_probe" 2>/dev/null) || true
is terminal-shell-ran-with-zle on "$(field ZLE "$term_text")"
is interactive-ctrl-t-fzf-file-widget fzf-file-widget "$(field CTRL_T "$term_text")"
is interactive-alt-c-fzf-cd-widget fzf-cd-widget "$(field ALT_C "$term_text")"
is interactive-ctrl-r-atuin-widget atuin-search "$(field CTRL_R "$term_text")"

# With no terminal, an interactive shell prints on stderr only what one with no
# zsh files prints: fzf's init script restores options through one that cannot
# change there.
no_terminal_stderr() { # <home>
  (cd "$work_dir" && detached env -i HOME="$1" TERM=xterm-256color PATH="$base_path" \
    "$zsh_bin" -i -c 'echo hi' </dev/null 2>&1 >/dev/null) || true
}
is no-terminal-stderr-as-bare "$(no_terminal_stderr "$bare_home")" \
  "$(no_terminal_stderr "$fix_home")"

# A stdout that is not a terminal gets the commands' output and nothing else,
# such as the escape sequences that turn mouse reporting off at the first prompt.
piped_stdout() { # <home>
  (cd "$work_dir" && printf 'echo hi\n' | detached env -i HOME="$1" TERM=xterm-256color \
    PATH="$base_path" "$zsh_bin" -i 2>/dev/null | od -c) || true
}
is piped-stdout-as-bare "$(piped_stdout "$bare_home")" "$(piped_stdout "$home")"

# Each XDG variable the caller sets is kept, ZDOTDIR follows XDG_CONFIG_HOME,
# and everything derived from an XDG directory follows it too. $HOME holds only
# ~/.zshenv here, so a file read from $HOME instead of $ZDOTDIR is missing.
alt_home=$work_dir/caller-xdg
mkdir -p "$alt_home/.nix-profile/bin"
cp "$home_src/.zshenv" "$alt_home/.zshenv" 2>/dev/null || :
mkdir -p "$alt_home/.config/dots-work/env"
echo 'export DOTS_STATIC_ENV=static-env' >"$alt_home/.config/dots-work/env/static.env"
alt=$work_dir/caller-dirs
mkdir -p "$alt/config"
cp -R "$home_src/.config/." "$alt/config/"
alt_env=(HOME="$alt_home" TERM=dumb PATH="$base_path"
  XDG_CONFIG_HOME="$alt/config" XDG_DATA_HOME="$alt/data"
  XDG_STATE_HOME="$alt/state" XDG_CACHE_HOME="$alt/cache")
alt_vars=$(env -i "${alt_env[@]}" "$zsh_bin" -c printenv 2>/dev/null) || true
is caller-xdg-config-home-kept "$alt/config" "$(field XDG_CONFIG_HOME "$alt_vars")"
is caller-xdg-data-home-kept "$alt/data" "$(field XDG_DATA_HOME "$alt_vars")"
is caller-xdg-state-home-kept "$alt/state" "$(field XDG_STATE_HOME "$alt_vars")"
is caller-xdg-cache-home-kept "$alt/cache" "$(field XDG_CACHE_HOME "$alt_vars")"
is caller-zdotdir-follows-config-home "$alt/config/zsh" "$(field ZDOTDIR "$alt_vars")"
is caller-atuin-home-follows-data-home "$alt/data/atuin" "$(field ATUIN_HOME "$alt_vars")"
is caller-atuin-config-dir-follows-config-home "$alt/config/atuin" \
  "$(field ATUIN_CONFIG_DIR "$alt_vars")"
is caller-static-env-from-home-config static-env "$(field DOTS_STATIC_ENV "$alt_vars")"
is caller-quiet-stderr "" \
  "$(env -i "${alt_env[@]}" "$zsh_bin" -c true 2>&1 >/dev/null)"
alt_path=$(env -i "${alt_env[@]}" "$zsh_bin" -c 'print -r -- $PATH' 2>/dev/null) || true
for name in mise-shims aqua-bin; do
  case $name in
  mise-shims) dir=$alt/data/mise/shims ;;
  aqua-bin) dir=$alt/data/aquaproj-aqua/bin ;;
  esac
  if (($(path_index "$dir" "$alt_path") > 0)); then
    ok "caller-path-$name"
  else
    fail "caller-path-$name" "$dir is not on PATH=$alt_path"
  fi
done

# The completion cache follows a caller-set XDG_CACHE_HOME, and nothing lands in
# ~/.cache instead.
cache_home=$(new_home caller-cache)
alt_cache=$work_dir/caller-cache-dir
cache_probe=$work_dir/caller-cache.vars
cache_log=$work_dir/caller-cache.log
run_interactive "$cache_home" "$cache_probe" "$cache_log" XDG_CACHE_HOME="$alt_cache"
ran_and_quiet caller-cache-interactive-shell "$cache_probe" "$cache_log"
dump=
if [[ -d $alt_cache/zsh ]]; then
  ok caller-cache-dir-created
  dump=$(find "$alt_cache/zsh" -type f | LC_ALL=C sort | sed -n 1p || true)
else
  fail caller-cache-dir-created "$alt_cache/zsh does not exist"
fi
if [[ -n $dump ]]; then
  ok caller-cache-holds-completion-dump
else
  fail caller-cache-holds-completion-dump "no completion dump under $alt_cache/zsh"
fi
if [[ -e $cache_home/.cache ]]; then
  fail caller-cache-home-cache-untouched \
    "$cache_home/.cache exists: $(cd "$cache_home" && find .cache | tr '\n' ' ')"
else
  ok caller-cache-home-cache-untouched
fi

echo "summary: $checks checks, $failures failed (zsh $zsh_bin, home $home_src)"
if ((failures > 0)); then exit 1; fi
