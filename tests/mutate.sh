#!/usr/bin/env bash
# Break one condition of the shell files at a time and require the checks in
# tests/shell.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. Every check has a mutant here except the `-ran` checks and
# terminal-shell-ran-with-zle, which guard this harness rather than the files
# under test, and
# fixtures-interactive-shell-log-quiet, whose run has every optional file in
# place and so cannot see one being read when it is missing.
# Env: ZSH_BIN overrides the zsh to test.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
zsh_bin=${ZSH_BIN:-$(command -v zsh)}
base_path=/usr/bin:/bin:/usr/sbin:/sbin

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
skipped=0

expect_pass() {
  local out
  if out=$("$repo_dir/tests/shell.sh" 2>&1); then
    echo "pass: the files as committed"
  else
    echo "FAIL: the files as committed should pass"
    grep '^FAIL' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

expect_caught() { # <check>... <description> <file> <old> <new>
  local checks=$1 description=$2 file=$3 old=$4 new=$5 dir out check missing
  dir=$(mktemp -d "$work_dir/mutant.XXXX")
  cp -R "$repo_dir/home/." "$dir/"
  OLD=$old NEW=$new python3 - "$dir/$file" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
  out=$("$repo_dir/tests/shell.sh" "$dir" 2>&1) || true
  missing=
  # The summary line proves the run reached the end: a crash that skips later
  # checks is a broken harness, not a caught mutant.
  grep -q '^summary:' <<<"$out" || missing=' (no summary line)'
  for check in $checks; do
    grep -q "^FAIL: $check:" <<<"$out" || missing="$missing $check"
  done
  if [[ -z $missing ]]; then
    echo "caught: $description"
  else
    echo "MISSED: $description (expected to fail:$missing)"
    grep -E '^(FAIL|summary)' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

# An /etc file read after ~/.zshenv can push what .zshenv set behind the system
# directories; macOS's /etc/zprofile does it with path_helper (measured). Where
# nothing does, removing .zprofile's fix changes no PATH and the mutant cannot be
# caught, so this asks the same question the check does before running it.
etc_reorders_login_path() {
  local home=$work_dir/reorder-probe reordered
  mkdir -p "$home/marker"
  printf 'path=($HOME/marker $path)\n' >"$home/.zshenv"
  reordered=$(env -i HOME="$home" TERM=dumb PATH="$base_path" "$zsh_bin" -lc \
    'print -r -- $(( ${path[(i)$HOME/marker]} > ${path[(i)/usr/bin]} ))')
  [[ $reordered == 1 ]]
}

expect_pass

expect_caught zdotdir 'ZDOTDIR is never set' \
  .zshenv 'export ZDOTDIR=$XDG_CONFIG_HOME/zsh' ''

expect_caught zdotdir 'ZDOTDIR is set but not exported' \
  .zshenv 'export ZDOTDIR=$XDG_CONFIG_HOME/zsh' 'ZDOTDIR=$XDG_CONFIG_HOME/zsh'

expect_caught caller-zdotdir-follows-config-home 'ZDOTDIR ignores XDG_CONFIG_HOME' \
  .zshenv 'export ZDOTDIR=$XDG_CONFIG_HOME/zsh' 'export ZDOTDIR=$HOME/.config/zsh'

expect_caught 'caller-quiet-stderr caller-atuin-home-follows-data-home' \
  '$ZDOTDIR/.zshenv is sourced from $HOME instead of $ZDOTDIR' \
  .zshenv 'source $ZDOTDIR/.zshenv' 'source $HOME/.config/zsh/.zshenv'

expect_caught xdg-config-home 'XDG_CONFIG_HOME defaults to the wrong directory' \
  .zshenv 'export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}' \
  'export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.configdir}'

expect_caught caller-xdg-config-home-kept 'XDG_CONFIG_HOME overrides the value the caller set' \
  .zshenv 'export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}' \
  'export XDG_CONFIG_HOME=$HOME/.config'

expect_caught caller-xdg-data-home-kept 'XDG_DATA_HOME overrides the value the caller set' \
  .zshenv 'export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}' \
  'export XDG_DATA_HOME=$HOME/.local/share'

expect_caught caller-xdg-state-home-kept 'XDG_STATE_HOME overrides the value the caller set' \
  .zshenv 'export XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}' \
  'export XDG_STATE_HOME=$HOME/.local/state'

expect_caught caller-xdg-cache-home-kept 'XDG_CACHE_HOME overrides the value the caller set' \
  .zshenv 'export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}' \
  'export XDG_CACHE_HOME=$HOME/.cache'

expect_caught xdg-data-home 'XDG_DATA_HOME defaults to the wrong directory' \
  .zshenv 'export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}' \
  'export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/sharedir}'

expect_caught xdg-data-home 'XDG_DATA_HOME is set but not exported' \
  .zshenv 'export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}' \
  'XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}'

expect_caught xdg-state-home 'XDG_STATE_HOME defaults to the wrong directory' \
  .zshenv 'export XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}' \
  'export XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/statedir}'

expect_caught xdg-cache-home 'XDG_CACHE_HOME defaults to the wrong directory' \
  .zshenv 'export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}' \
  'export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cachedir}'

expect_caught xdg-cache-home 'XDG_CACHE_HOME follows XDG_CONFIG_HOME' \
  .zshenv 'export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}' \
  'export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$XDG_CONFIG_HOME/cache}'

expect_caught atuin-home 'ATUIN_HOME is never set, so atuin falls back to ~/.atuin' \
  .config/zsh/.zshenv 'export ATUIN_HOME=$XDG_DATA_HOME/atuin' ''

expect_caught atuin-home 'ATUIN_HOME is set but not exported' \
  .config/zsh/.zshenv 'export ATUIN_HOME=$XDG_DATA_HOME/atuin' \
  'ATUIN_HOME=$XDG_DATA_HOME/atuin'

expect_caught caller-atuin-home-follows-data-home 'ATUIN_HOME ignores XDG_DATA_HOME' \
  .config/zsh/.zshenv 'export ATUIN_HOME=$XDG_DATA_HOME/atuin' \
  'export ATUIN_HOME=$HOME/.local/share/atuin'

expect_caught atuin-config-dir 'ATUIN_CONFIG_DIR is never set, so atuin reads $ATUIN_HOME/config.toml' \
  .config/zsh/.zshenv $'export ATUIN_CONFIG_DIR=$XDG_CONFIG_HOME/atuin\n' ''

expect_caught atuin-config-dir 'ATUIN_CONFIG_DIR is set but not exported' \
  .config/zsh/.zshenv 'export ATUIN_CONFIG_DIR=$XDG_CONFIG_HOME/atuin' \
  'ATUIN_CONFIG_DIR=$XDG_CONFIG_HOME/atuin'

expect_caught caller-atuin-config-dir-follows-config-home 'ATUIN_CONFIG_DIR ignores XDG_CONFIG_HOME' \
  .config/zsh/.zshenv 'export ATUIN_CONFIG_DIR=$XDG_CONFIG_HOME/atuin' \
  'export ATUIN_CONFIG_DIR=$HOME/.config/atuin'

expect_caught editor 'EDITOR is never set' \
  .config/zsh/.zshenv 'export EDITOR=nvim' ''

expect_caught visual 'VISUAL is never set' \
  .config/zsh/.zshenv $'export VISUAL=nvim\n' ''

expect_caught pager 'PAGER is never set' \
  .config/zsh/.zshenv $'export PAGER=less\n' ''

expect_caught manpager 'MANPAGER is never set' \
  .config/zsh/.zshenv $'export MANPAGER=\'less -R\'\n' ''

expect_caught lang-c-utf8-when-en-us-absent 'LANG is en_US.UTF-8 whether or not the system has it' \
  .config/zsh/.zshenv 'export LANG=C.UTF-8' 'export LANG=en_US.UTF-8'

expect_caught lang-c-utf8-when-en-us-absent 'the fallback LANG is set but not exported' \
  .config/zsh/.zshenv 'export LANG=C.UTF-8' 'LANG=C.UTF-8'

expect_caught lang-c-utf8-when-en-us-absent \
  'the LANG probe keeps the inherited locale, so a UTF-8 one passes for en_US.UTF-8' \
  .config/zsh/.zshenv 'local LC_ALL=C; ' 'local LC_ALL; '

# The host's own answer, as tests/shell.sh asks it: where libc cannot load
# en_US.UTF-8, the check expects C.UTF-8 and these mutants cannot be caught.
if [[ $(env -i LC_ALL=en_US.UTF-8 locale charmap 2>/dev/null) == UTF-8 ]]; then
  expect_caught lang-en-us-where-libc-has-it 'the LANG probe expects a codeset libc never names' \
    .config/zsh/.zshenv '[[ $langinfo[CODESET] == UTF-8 ]]' '[[ $langinfo[CODESET] == utf8 ]]'
  expect_caught lang-en-us-where-libc-has-it 'LANG is C.UTF-8 even where libc has en_US.UTF-8' \
    .config/zsh/.zshenv 'export LANG=en_US.UTF-8' 'export LANG=C.UTF-8'
else
  echo "n/a: libc here cannot load en_US.UTF-8, so the en_US.UTF-8 branch cannot be mutation-tested"
  skipped=$((skipped + 2))
fi

expect_caught kubeconfig-lists-config-then-yaml 'KUBECONFIG lists the yaml files before config' \
  .config/zsh/.zshenv '($HOME/.kube/config(N-.) $HOME/.kube/*.yaml(N-.))' \
  '($HOME/.kube/*.yaml(N-.) $HOME/.kube/config(N-.))'

expect_caught kubeconfig-lists-config-then-yaml 'KUBECONFIG lists every file in ~/.kube' \
  .config/zsh/.zshenv '$HOME/.kube/*.yaml(N-.)' '$HOME/.kube/*(N-.)'

expect_caught kubeconfig-lists-config-then-yaml \
  'KUBECONFIG lists a *.yaml that is a directory or a dangling symlink' \
  .config/zsh/.zshenv '$HOME/.kube/*.yaml(N-.)' '$HOME/.kube/*.yaml(N)'

expect_caught kubeconfig-lists-config-then-yaml 'KUBECONFIG leaves out a *.yaml symlink to a file' \
  .config/zsh/.zshenv '$HOME/.kube/*.yaml(N-.)' '$HOME/.kube/*.yaml(N.)'

expect_caught kubeconfig-skips-config-directory 'KUBECONFIG lists ~/.kube/config when it is a directory' \
  .config/zsh/.zshenv '$HOME/.kube/config(N-.)' '$HOME/.kube/config(N)'

expect_caught kubeconfig-drops-names-with-colon 'KUBECONFIG lists a name that holds a colon' \
  .config/zsh/.zshenv $'    kube_files=(${kube_files:#*:*})\n' ''

expect_caught kubeconfig-lists-config-then-yaml 'KUBECONFIG is set but not exported' \
  .config/zsh/.zshenv 'export KUBECONFIG=' 'KUBECONFIG='

expect_caught kubeconfig-unset-without-kube-dir 'KUBECONFIG is exported empty with no ~/.kube' \
  .config/zsh/.zshenv $'    if (( $#kube_files )); then\n      export KUBECONFIG=${(j.:.)kube_files}\n    fi' \
  '    export KUBECONFIG=${(j.:.)kube_files}'

expect_caught 'nonlogin-quiet-stderr login-quiet-stderr' \
  'the KUBECONFIG globs fail with no ~/.kube' \
  .config/zsh/.zshenv '$HOME/.kube/config(N-.)' '$HOME/.kube/config(-.)'

expect_caught kubeconfig-caller-value-kept 'KUBECONFIG replaces the value the caller set' \
  .config/zsh/.zshenv 'if [[ -z ${KUBECONFIG-} ]]; then' 'if true; then'

expect_caught kube-dir-env-unchanged-apart-from-kubeconfig \
  'the KUBECONFIG list is globbed after a cd, which changes PWD' \
  .config/zsh/.zshenv 'local kube_files=($HOME/.kube/config(N-.) $HOME/.kube/*.yaml(N-.))' \
  'cd $HOME/.kube; local kube_files=($PWD/config(N-.) $PWD/*.yaml(N-.))'

expect_caught kube-dir-output-unchanged 'the KUBECONFIG block prints the list' \
  .config/zsh/.zshenv '      export KUBECONFIG=${(j.:.)kube_files}' \
  $'      export KUBECONFIG=${(j.:.)kube_files}\n      print -r -- $KUBECONFIG'

# One directory at a time off the PATH list, which must fail the same checks in
# both a non-login and a login shell.
expect_caught 'path-nix-profile login-path-nix-profile login-path-nix-profile-before-usr-bin nonlogin-git-from-nix-profile login-git-from-nix-profile' \
  'the Nix user profile is left off PATH' \
  .config/zsh/.zshenv $'  $HOME/.nix-profile/bin\n' ''

expect_caught 'path-per-user login-path-per-user login-path-per-user-before-usr-bin' \
  'the per-user Nix profile is left off PATH' \
  .config/zsh/.zshenv $'  /etc/profiles/per-user/$USERNAME/bin\n' ''

expect_caught 'path-per-user login-path-per-user login-path-per-user-before-usr-bin' \
  'the per-user Nix profile uses $USER, which is empty without a login' \
  .config/zsh/.zshenv '/etc/profiles/per-user/$USERNAME/bin' \
  '/etc/profiles/per-user/$USER/bin'

expect_caught 'path-current-system login-path-current-system login-path-current-system-before-usr-bin' \
  'the system profile is left off PATH' \
  .config/zsh/.zshenv $'  /run/current-system/sw/bin\n' ''

expect_caught 'path-nix-default login-path-nix-default login-path-nix-default-before-usr-bin' \
  "Nix's default profile is left off PATH" \
  .config/zsh/.zshenv $'  /nix/var/nix/profiles/default/bin\n' ''

expect_caught 'path-local-bin login-path-local-bin login-path-local-bin-before-usr-bin' \
  '$HOME/.local/bin is left off PATH' \
  .config/zsh/.zshenv $'  $HOME/.local/bin\n' ''

expect_caught 'path-mise-shims login-path-mise-shims login-path-mise-shims-before-usr-bin' \
  "mise's shims are left off PATH" \
  .config/zsh/.zshenv $'  $XDG_DATA_HOME/mise/shims\n' ''

expect_caught caller-path-mise-shims "mise's shims ignore XDG_DATA_HOME" \
  .config/zsh/.zshenv '$XDG_DATA_HOME/mise/shims' '$HOME/.local/share/mise/shims'

expect_caught 'path-aqua-bin login-path-aqua-bin login-path-aqua-bin-before-usr-bin' \
  "aqua's bin directory is left off PATH" \
  .config/zsh/.zshenv $'  $XDG_DATA_HOME/aquaproj-aqua/bin\n' ''

expect_caught caller-path-aqua-bin "aqua's bin directory ignores XDG_DATA_HOME" \
  .config/zsh/.zshenv '$XDG_DATA_HOME/aquaproj-aqua/bin' \
  '$HOME/.local/share/aquaproj-aqua/bin'

expect_caught 'nonlogin-quiet-stdout login-quiet-stdout' \
  'a startup file prints to stdout' \
  .config/zsh/.zshenv 'export EDITOR=nvim' $'export EDITOR=nvim\necho loaded'

expect_caught 'nonlogin-quiet-stderr login-quiet-stderr caller-quiet-stderr' \
  'a startup file prints to stderr' \
  .config/zsh/.zshenv 'export EDITOR=nvim' $'export EDITOR=nvim\necho loaded >&2'

expect_caught 'static-env-sourced caller-static-env-from-home-config' \
  'the work profile is never sourced' \
  .config/zsh/.zshenv $'if [[ -r $HOME/.config/dots-work/env/static.env ]]; then\n  source $HOME/.config/dots-work/env/static.env\nfi\n' ''

expect_caught caller-static-env-from-home-config \
  'the work profile is read from XDG_CONFIG_HOME instead of ~/.config' \
  .config/zsh/.zshenv \
  $'if [[ -r $HOME/.config/dots-work/env/static.env ]]; then\n  source $HOME/.config/dots-work/env/static.env' \
  $'if [[ -r $XDG_CONFIG_HOME/dots-work/env/static.env ]]; then\n  source $XDG_CONFIG_HOME/dots-work/env/static.env'

expect_caught 'nonlogin-quiet-stderr login-quiet-stderr' \
  'the work profile is sourced even when it does not exist' \
  .config/zsh/.zshenv \
  $'if [[ -r $HOME/.config/dots-work/env/static.env ]]; then\n  source $HOME/.config/dots-work/env/static.env\nfi' \
  'source $HOME/.config/dots-work/env/static.env'

expect_caught home-tree-unchanged-by-noninteractive \
  'a non-interactive shell creates the completion cache directory' \
  .config/zsh/.zshenv 'export EDITOR=nvim' \
  $'export EDITOR=nvim\nmkdir -p $XDG_CACHE_HOME/zsh'

expect_caught interactive-savehist-zero 'zsh is allowed to save history' \
  .config/zsh/.zshrc 'SAVEHIST=0' 'SAVEHIST=1000'

expect_caught interactive-histfile-unset 'HISTFILE stays set' \
  .config/zsh/.zshrc 'unset HISTFILE' 'HISTFILE=$HOME/.zsh_history'

expect_caught 'no-history-file home-allowlist' 'an interactive shell writes a zsh history file' \
  .config/zsh/.zshrc 'unset HISTFILE' $'HISTFILE=$HOME/.zsh_history\nSAVEHIST=1000'

expect_caught interactive-histsize-keeps-a-session \
  'in-memory history holds one line, so up-arrow is useless' \
  .config/zsh/.zshrc 'HISTSIZE=100000' 'HISTSIZE=1'

# Ceiling: on a switched nix-darwin host, /etc/zshrc runs `bindkey -e` and sets
# HIST_IGNORE_DUPS, and /etc/zshenv puts ~/.nix-profile's site-functions on
# fpath, so there the keymap, HIST_IGNORE_DUPS and fpath mutants survive.
expect_caught interactive-keymap-emacs 'EDITOR=nvim leaves zsh in the vi keymap' \
  .config/zsh/.zshrc $'bindkey -e\n' ''

expect_caught interactive-option-interactivecomments 'INTERACTIVE_COMMENTS is left off' \
  .config/zsh/.zshrc 'INTERACTIVE_COMMENTS ' ''

expect_caught interactive-option-autocd 'AUTO_CD is left off' \
  .config/zsh/.zshrc ' AUTO_CD' ''

expect_caught interactive-option-autopushd 'AUTO_PUSHD is left off' \
  .config/zsh/.zshrc ' AUTO_PUSHD' ''

expect_caught interactive-option-pushdignoredups 'PUSHD_IGNORE_DUPS is left off' \
  .config/zsh/.zshrc ' PUSHD_IGNORE_DUPS' ''

expect_caught interactive-option-no-beep 'the shell still beeps' \
  .config/zsh/.zshrc ' NO_BEEP' ''

expect_caught interactive-option-histignoredups 'HIST_IGNORE_DUPS is left off' \
  .config/zsh/.zshrc ' HIST_IGNORE_DUPS' ''

expect_caught 'completion-dump-created caller-cache-holds-completion-dump' \
  'the completion cache directory is not created, so compinit writes no dump' \
  .config/zsh/.zshrc 'mkdir -p $XDG_CACHE_HOME/zsh' ''

expect_caught 'caller-cache-holds-completion-dump caller-cache-home-cache-untouched' \
  'the completion cache directory ignores XDG_CACHE_HOME' \
  .config/zsh/.zshrc 'mkdir -p $XDG_CACHE_HOME/zsh' 'mkdir -p $HOME/.cache/zsh'

expect_caught home-tree-adds-only-cache 'the completion dump lands outside the cache directory' \
  .config/zsh/.zshrc 'compinit -i -d $XDG_CACHE_HOME/zsh/zcompdump' 'compinit -i'

expect_caught caller-cache-holds-completion-dump 'completion is never initialized' \
  .config/zsh/.zshrc 'compinit -i -d $XDG_CACHE_HOME/zsh/zcompdump' ''

expect_caught insecure-fpath-completion-initialized \
  'compinit asks about an insecure fpath directory, and with no terminal to answer it aborts' \
  .config/zsh/.zshrc 'compinit -i -d' 'compinit -d'

expect_caught 'completion-cache-in-xdg-cache home-allowlist' \
  'the completion cache lands in $HOME' \
  .config/zsh/.zshrc 'cache-path $XDG_CACHE_HOME/zsh/zcompcache' 'cache-path $HOME/.zcompcache'

expect_caught completion-cache-in-xdg-cache 'completion functions never use their cache' \
  .config/zsh/.zshrc "use-cache on" "use-cache off"

expect_caught interactive-profile-completion-registered \
  "the Nix profiles' completions are left off fpath" \
  .config/zsh/.zshrc $'fpath=(${^_dots_path:h}/share/zsh/site-functions(N/) $fpath)\n' ''

expect_caught interactive-skip-global-compinit "Ubuntu's global compinit is left on" \
  .config/zsh/.zshenv $'skip_global_compinit=1\n' ''

expect_caught 'interactive-promptsubst-off interactive-prompt-without-command-substitution' \
  'the prompt runs a command on every redraw' \
  .config/zsh/.zshrc "PROMPT='%~ %# '" \
  $'setopt prompt_subst\nPROMPT=\'$(git branch --show-current 2>/dev/null) %~ %# \''

expect_caught interactive-no-aliases-added 'an alias shadows a command' \
  .config/zsh/.zshrc "PROMPT='%~ %# '" $'PROMPT=\'%~ %# \'\nalias rm="rm -i"'

expect_caught interactive-ctrl-g-dots-widget 'Ctrl+g is left unbound' \
  .config/zsh/.zshrc $'  bindkey \'^g\' dots-ghq-cd\n' ''

expect_caught interactive-ctrl-g-dots-widget 'the ghq widget is bound to another key' \
  .config/zsh/.zshrc "bindkey '^g' dots-ghq-cd" "bindkey '^t' dots-ghq-cd"

expect_caught 'interactive-ctrl-t-fzf-file-widget interactive-alt-c-fzf-cd-widget' \
  "fzf's key bindings are never loaded" \
  .config/zsh/.zshrc $'  if [[ -n $TTY ]]; then\n    eval "$(fzf --zsh)"\n  fi\n' ''

expect_caught no-terminal-stderr-empty \
  "fzf's key bindings load without a terminal, and its option restore fails on zle" \
  .config/zsh/.zshrc $'  if [[ -n $TTY ]]; then\n    eval "$(fzf --zsh)"\n  fi\n' \
  $'  eval "$(fzf --zsh)"\n'

expect_caught no-terminal-stderr-empty \
  "fzf's key bindings wait for the zle option, which reads on while .zshrc runs" \
  .config/zsh/.zshrc '[[ -n $TTY ]]' '[[ -o zle ]]'

expect_caught interactive-ctrl-r-atuin-widget "fzf's key bindings load after atuin's and take Ctrl+r" \
  .config/zsh/.zshrc '  eval "$(atuin init zsh --disable-up-arrow)"' \
  $'  eval "$(atuin init zsh --disable-up-arrow)"\n  eval "$(fzf --zsh)"'

expect_caught interactive-ctrl-r-atuin-widget 'atuin is never initialized' \
  .config/zsh/.zshrc $'if (( $+commands[atuin] )); then\n  eval "$(atuin init zsh --disable-up-arrow)"\nfi\n' ''

expect_caught interactive-ctrl-r-atuin-widget "atuin is told to leave Ctrl+r alone" \
  .config/zsh/.zshrc 'atuin init zsh --disable-up-arrow' \
  'atuin init zsh --disable-ctrl-r'

expect_caught interactive-abbreviation-expands 'an abbreviation is left as typed' \
  .config/zsh/.zshrc '    LBUFFER=${dots_abbreviations[$LBUFFER]}' '    :'

expect_caught interactive-abbreviation-ll 'll is left out of the abbreviations' \
  .config/zsh/.zshrc $'  ll \'eza -l --git\'\n' ''

expect_caught interactive-abbreviation-la 'la lists without hidden files' \
  .config/zsh/.zshrc "la 'eza -la --git'" "la 'eza -l --git'"

expect_caught interactive-abbreviation-lt 'lt is left out of the abbreviations' \
  .config/zsh/.zshrc $'  lt \'eza --tree --level=2\'\n' ''

expect_caught interactive-abbreviation-b 'b is left out of the abbreviations' \
  .config/zsh/.zshrc $'  b bat\n' ''

expect_caught interactive-abbreviation-not-with-text-right \
  'a word with text to its right expands, so Ctrl+a then g runs gitit status' \
  .config/zsh/.zshrc ' && -z $RBUFFER' ''

expect_caught interactive-abbreviation-not-in-vared 'an abbreviation expands in vared' \
  .config/zsh/.zshrc '$CONTEXT == start && ' ''

expect_caught interactive-abbreviation-not-after-pending-lines \
  'an abbreviation expands after lines still pending' \
  .config/zsh/.zshrc ' && -z $PREBUFFER' ''

expect_caught 'interactive-abbreviation-not-on-continuation interactive-abbreviation-not-in-vared' \
  'an abbreviation expands inside an open quote or a heredoc' \
  .config/zsh/.zshrc '$CONTEXT == start && -z $PREBUFFER && ' ''

expect_caught interactive-space-expands-abbreviations 'Space inserts a space without expanding' \
  .config/zsh/.zshrc $'bindkey \' \' dots-abbreviation-space\n' ''

expect_caught interactive-enter-expands-abbreviations 'Enter runs the line without expanding' \
  .config/zsh/.zshrc $'bindkey \'^m\' dots-abbreviation-accept\n' ''

expect_caught interactive-enter-clears-suggestion \
  "zsh-autosuggestions redraws its suggestion on the line Enter accepted" \
  .config/zsh/.zshrc $'ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(dots-abbreviation-accept)\n' ''

expect_caught interactive-abbreviations-shadow-nothing 'an abbreviation shadows a command' \
  .config/zsh/.zshrc $'  v nvim\n' $'  v nvim\n  vi nvim\n'

expect_caught interactive-abbreviations-shadow-nothing 'an abbreviation shadows a command from the Nix profile' \
  .config/zsh/.zshrc $'  v nvim\n' $'  v nvim\n  rg \'rg --hidden\'\n'

expect_caught interactive-abbreviations-shadow-nothing 'an abbreviation shadows a reserved word' \
  .config/zsh/.zshrc $'  v nvim\n' $'  v nvim\n  foreach \'git log\'\n'

expect_caught piped-stdout-as-bare 'the mouse reporting reset writes escape bytes into a pipe' \
  .config/zsh/.zshrc '[[ -t 1 ]]' 'true'

expect_caught interactive-zshrc-local-from-zdotdir \
  'the local zsh override is never sourced' \
  .config/zsh/.zshrc $'if [[ -r $ZDOTDIR/.zshrc.local ]]; then\n  source $ZDOTDIR/.zshrc.local\nfi\n' ''

expect_caught interactive-zshrc-local-from-zdotdir \
  'the local zsh override is read from $HOME instead of $ZDOTDIR' \
  .config/zsh/.zshrc \
  $'if [[ -r $ZDOTDIR/.zshrc.local ]]; then\n  source $ZDOTDIR/.zshrc.local' \
  $'if [[ -r $HOME/.zshrc.local ]]; then\n  source $HOME/.zshrc.local'

expect_caught 'interactive-shell-log-quiet caller-cache-interactive-shell-log-quiet insecure-fpath-interactive-shell-log-quiet' \
  'the local zsh override is sourced even when it does not exist' \
  .config/zsh/.zshrc \
  $'if [[ -r $ZDOTDIR/.zshrc.local ]]; then\n  source $ZDOTDIR/.zshrc.local\nfi' \
  'source $ZDOTDIR/.zshrc.local'

if etc_reorders_login_path; then
  expect_caught 'login-path-nix-profile-before-usr-bin login-path-per-user-before-usr-bin login-path-current-system-before-usr-bin login-path-nix-default-before-usr-bin login-path-local-bin-before-usr-bin login-path-mise-shims-before-usr-bin login-path-aqua-bin-before-usr-bin login-git-from-nix-profile' \
    '.zprofile does not re-front the Nix directories' \
    .config/zsh/.zprofile 'path=($_dots_path $path)' ''
  expect_caught 'login-path-per-user-before-usr-bin login-path-current-system-before-usr-bin login-path-nix-default-before-usr-bin login-path-local-bin-before-usr-bin login-path-mise-shims-before-usr-bin login-path-aqua-bin-before-usr-bin' \
    '.zprofile re-fronts the first directory only' \
    .config/zsh/.zprofile 'path=($_dots_path $path)' 'path=($HOME/.nix-profile/bin $path)'
elif [[ $(uname) == Darwin ]]; then
  # macOS reorders login PATH with path_helper, so a probe that says otherwise is
  # broken rather than reporting a machine where .zprofile's fix is untestable.
  echo "FAIL: the reorder probe found no /etc file that reorders login PATH on macOS"
  failures=$((failures + 1))
else
  echo "n/a: no /etc file reorders login PATH here, so .zprofile's fix cannot be mutation-tested on this machine"
  skipped=$((skipped + 2))
fi

if ((failures > 0)); then
  echo "$failures mutation check(s) failed"
  exit 1
fi
if ((skipped > 0)); then
  echo "every mutant is caught ($skipped skipped)"
else
  echo "every mutant is caught"
fi
