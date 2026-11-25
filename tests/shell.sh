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
# rather than from /usr/bin.
new_home() { # <name>
  local home=$work_dir/$1
  mkdir -p "$home/.nix-profile/bin"
  cp -R "$home_src/." "$home/"
  printf '#!/bin/sh\necho fake-nix-profile-git\n' >"$home/.nix-profile/bin/git"
  chmod +x "$home/.nix-profile/bin/git"
  echo "$home"
}

# The commands `.zshrc` binds keys for. The atuin stub prints the same shape of
# init script atuin does, including the Ctrl+r binding it leaves out when it is
# told to.
add_command_stubs() { # <home>
  local bin=$1/.nix-profile/bin
  printf '#!/bin/sh\nexit 0\n' >"$bin/ghq"
  printf '#!/bin/sh\nexit 0\n' >"$bin/fzf"
  cat >"$bin/atuin" <<'STUB'
#!/bin/sh
echo '_atuin_search_widget() { : }'
echo 'zle -N _atuin_search_widget'
case " $* " in
*" --disable-ctrl-r "*) ;;
*) echo "bindkey '^r' _atuin_search_widget" ;;
esac
STUB
  chmod +x "$bin/ghq" "$bin/fzf" "$bin/atuin"
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
  print -r -- "SAVEHIST=\$SAVEHIST"
  print -r -- "HISTFILE=\${HISTFILE-}"
  print -r -- "HISTSIZE=\$HISTSIZE"
  print -r -- "PROMPT=\$PROMPT"
  if [[ -o promptsubst ]]; then print -r -- "PROMPTSUBST=on"; else print -r -- "PROMPTSUBST=off"; fi
  ctrl_g=\$(bindkey '^g'); ctrl_g=\${ctrl_g##* }
  ctrl_r=\$(bindkey '^r'); ctrl_r=\${ctrl_r##* }
  print -r -- "CTRL_G=\$ctrl_g"
  print -r -- "CTRL_G_TYPE=\${widgets[\$ctrl_g]-none}"
  print -r -- "CTRL_R=\$ctrl_r"
  print -r -- "LOCAL_RC=\${DOTS_LOCAL_RC-}"
  alias | sed 's/^/ALIAS /'
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
    env -i HOME="$home" TERM=dumb PATH="$base_path" "$@" "$zsh_bin" -i \
      <"$out.zsh" >"$log" 2>&1) || true
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
  is "$1-log-quiet" "" "$(error_lines "$3" | tr '\n' ' ')"
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
is editor nvim "$(field EDITOR "$vars")"

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

# "Aliases: none by default": compare with a HOME that has no zsh files at all,
# so zsh's own aliases and anything /etc adds are not counted.
bare_home=$work_dir/bare
mkdir -p "$bare_home"
bare_probe=$work_dir/bare.vars
run_interactive "$bare_home" "$bare_probe" "$work_dir/bare.log"
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

stray=
for entry in $(cd "$home" && ls -A); do
  case $entry in
  .zshenv | .config | .cache | .nix-profile) ;;
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
# override in $ZDOTDIR, and the commands whose key bindings .zshrc sets up.
fix_home=$(new_home fixtures)
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
# Ctrl+g runs the repository's ghq widget (a user widget, whatever it is named)
# and Ctrl+r runs the widget atuin's init script binds.
is interactive-ctrl-g-dots-widget "user:$(field CTRL_G "$fix_text")" \
  "$(field CTRL_G_TYPE "$fix_text")"
is interactive-ctrl-r-atuin-widget _atuin_search_widget "$(field CTRL_R "$fix_text")"

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
  dump=$(find "$alt_cache/zsh" -type f | LC_ALL=C sort | head -1)
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
