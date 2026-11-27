#!/usr/bin/env bash
# Check how tests/lib/mutate.sh picks the runners a pull request runs: from a
# list of changed paths, a runner runs when one of them is an input of its own,
# or under .github/workflows/, or flake.nix or flake.lock; and a diff it cannot
# compute runs it. The lists are fixtures, not a git diff.
# Usage: tests/selection.sh [helper]   (default: tests/lib/mutate.sh)
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/mutate.sh
source "${1:-$repo_dir/tests/lib/mutate.sh}"

checks=0
failures=0

check() { # <name> <runs|skips> <changed path>...
  local name=$1 want=$2 got=skips
  shift 2
  checks=$((checks + 1))
  mutate_inputs_changed "$(printf '%s\n' "$@")" && got=runs
  if [[ $got == "$want" ]]; then
    echo "ok: $name"
  else
    failures=$((failures + 1))
    echo "FAIL: $name: want $want, got $got"
  fi
}

mutate_inputs nix/ssh_config home tests/ssh.sh tests/lib/

check docs-only skips README.md docs/design.md
check no-change skips
check subject-file runs nix/ssh_config
check below-input-directory runs home/.config/zsh/.zshrc
check input-directory-itself runs home
check test-script runs tests/ssh.sh
check helper-directory runs tests/lib/mutate.sh
check second-path-matches runs README.md tests/ssh.sh
check sibling-of-input-file skips nix/ssh_config.bak nix/home.nix
check prefix-of-input-directory skips home2/file tests/library.sh
check workflow runs .github/workflows/shell.yml
check flake-lock runs flake.lock
check flake-nix runs flake.nix
check blank-line-only skips ''

checks=$((checks + 1))
# Not in a subshell, which would keep the mode it sets from this one.
MUTATE_BASE=refs/heads/no-such-branch-for-selection mutate_select >"$mutate_dir/select.out"
out=$(<"$mutate_dir/select.out")
if [[ $mutate_mode == full && $out == "mode: full (no diff against "* ]]; then
  echo "ok: unknown-diff-runs-everything"
else
  failures=$((failures + 1))
  echo "FAIL: unknown-diff-runs-everything: mode '$mutate_mode', printed '$out'"
fi

echo "summary: $checks checks, $failures failed"
((failures == 0))
