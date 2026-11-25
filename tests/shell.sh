#!/usr/bin/env bash
# Check that zsh starts with the layout that docs/design.md "Shell" specifies,
# with no Nix switch: a temporary HOME holds only the files from <home-dir>
# (default home/), and `env -i` starts zsh as `zsh -c`, `zsh -lc`, and an
# interactive shell fed commands on stdin.
# Usage: tests/shell.sh [home-dir]   Env: ZSH_BIN overrides the zsh to test.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
home_src=${1:-$repo_dir/home}
zsh_bin=${ZSH_BIN:-$(command -v zsh)}
base_path=/usr/bin:/bin:/usr/sbin:/sbin

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

run_zsh() { # <home> <zsh-arg>...
  local home=$1
  shift
  env -i HOME="$home" TERM=dumb PATH="$base_path" "$zsh_bin" "$@"
}

run_zsh_with() { # <home> <VAR=VALUE> <zsh-arg>...
  local home=$1 assignment=$2
  shift 2
  env -i HOME="$home" TERM=dumb PATH="$base_path" "$assignment" "$zsh_bin" "$@"
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

tree_of() { # <dir>
  (cd "$1" && find . | LC_ALL=C sort)
}

print_vars='for v in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME ZDOTDIR ATUIN_HOME
do print -r -- "$v=${(P)v}"; done'

home=$(new_home default)
before_tree=$(tree_of "$home")

vars=$(run_zsh "$home" -c "$print_vars" 2>/dev/null) || true
is xdg-config-home "$home/.config" "$(field XDG_CONFIG_HOME "$vars")"
is xdg-data-home "$home/.local/share" "$(field XDG_DATA_HOME "$vars")"
is xdg-state-home "$home/.local/state" "$(field XDG_STATE_HOME "$vars")"
is xdg-cache-home "$home/.cache" "$(field XDG_CACHE_HOME "$vars")"
is zdotdir "$home/.config/zsh" "$(field ZDOTDIR "$vars")"
is atuin-home "$home/.local/share/atuin" "$(field ATUIN_HOME "$vars")"

is nonlogin-git-from-nix-profile "$home/.nix-profile/bin/git" \
  "$(run_zsh "$home" -c 'command -v git' 2>/dev/null)"

login_path=$(run_zsh "$home" -lc 'print -r -- $PATH' 2>/dev/null) || true
nix_pos=$(path_index "$home/.nix-profile/bin" "$login_path")
usr_pos=$(path_index /usr/bin "$login_path")
if ((nix_pos > 0 && usr_pos > 0 && nix_pos < usr_pos)); then
  ok login-path-nix-before-usr-bin
else
  fail login-path-nix-before-usr-bin \
    "nix profile at $nix_pos, /usr/bin at $usr_pos in PATH=$login_path"
fi
is login-git-from-nix-profile "$home/.nix-profile/bin/git" \
  "$(run_zsh "$home" -lc 'command -v git' 2>/dev/null)"

probe=$work_dir/interactive.vars
log=$work_dir/interactive.log
printf 'print -r -- "SAVEHIST=$SAVEHIST" > %q\nprint -r -- "HISTFILE=${HISTFILE-}" >> %q\nprint -r -- "DONE=yes" >> %q\nexit\n' \
  "$probe" "$probe" "$probe" | run_zsh "$home" -i >"$log" 2>&1 || true

if [[ -f $probe ]] && grep -q '^DONE=yes$' "$probe"; then
  ok interactive-shell-ran
else
  fail interactive-shell-ran "no probe output; log: $(tr '\n' ' ' <"$log" | cut -c1-200)"
fi
probe_text=$(cat "$probe" 2>/dev/null) || true
is interactive-savehist-zero 0 "$(field SAVEHIST "$probe_text")"
is interactive-histfile-unset "" "$(field HISTFILE "$probe_text")"

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

alt_home=$(new_home caller-xdg)
alt_config=$work_dir/caller-xdg-config
mkdir -p "$alt_config"
cp -R "$home_src/.config/." "$alt_config/"
alt_vars=$(run_zsh_with "$alt_home" "XDG_CONFIG_HOME=$alt_config" -c "$print_vars" 2>/dev/null) || true
is caller-xdg-config-home-kept "$alt_config" "$(field XDG_CONFIG_HOME "$alt_vars")"
is caller-zdotdir-follows-config-home "$alt_config/zsh" "$(field ZDOTDIR "$alt_vars")"
is caller-xdg-cache-home-still-default "$alt_home/.cache" "$(field XDG_CACHE_HOME "$alt_vars")"

echo "summary: $checks checks, $failures failed (zsh $zsh_bin, home $home_src)"
if ((failures > 0)); then exit 1; fi
