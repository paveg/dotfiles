#!/usr/bin/env bash
# Break one condition of the shell files at a time and require the checks in
# tests/shell.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. Every check has a mutant here except interactive-shell-ran,
# which guards this harness rather than the files under test.
# Env: ZSH_BIN overrides the zsh to test.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
zsh_bin=${ZSH_BIN:-$(command -v zsh)}
base_path=/usr/bin:/bin:/usr/sbin:/sbin

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0

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

expect_caught caller-zdotdir-follows-config-home 'ZDOTDIR ignores XDG_CONFIG_HOME' \
  .zshenv 'export ZDOTDIR=$XDG_CONFIG_HOME/zsh' 'export ZDOTDIR=$HOME/.config/zsh'

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

expect_caught 'nonlogin-git-from-nix-profile login-git-from-nix-profile' \
  'the Nix user profile is left off PATH' \
  .config/zsh/.zshenv $'  $HOME/.nix-profile/bin\n' ''

expect_caught interactive-savehist-zero 'zsh is allowed to save history' \
  .config/zsh/.zshrc 'SAVEHIST=0' 'SAVEHIST=1000'

expect_caught interactive-histfile-unset 'HISTFILE stays set' \
  .config/zsh/.zshrc 'unset HISTFILE' 'HISTFILE=$HOME/.zsh_history'

expect_caught 'no-history-file home-allowlist' 'an interactive shell writes a zsh history file' \
  .config/zsh/.zshrc 'unset HISTFILE' $'HISTFILE=$HOME/.zsh_history\nSAVEHIST=1000'

expect_caught cache-dir-created 'the completion cache directory is not created' \
  .config/zsh/.zshrc 'mkdir -p $XDG_CACHE_HOME/zsh' ''

expect_caught home-tree-adds-only-cache 'the completion dump lands outside the cache directory' \
  .config/zsh/.zshrc 'compinit -i -d $XDG_CACHE_HOME/zsh/zcompdump' 'compinit -i'

if etc_reorders_login_path; then
  expect_caught login-path-nix-before-usr-bin '.zprofile does not re-front the Nix directories' \
    .config/zsh/.zprofile 'path=($_dots_path $path)' ''
else
  echo "n/a: no /etc file reorders login PATH here, so .zprofile's fix cannot be mutation-tested on this machine"
fi

if ((failures > 0)); then
  echo "$failures mutation check(s) failed"
  exit 1
fi
echo "every mutant is caught"
