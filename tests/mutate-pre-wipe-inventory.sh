#!/usr/bin/env bash
# Break one condition of scripts/pre-wipe-inventory.sh at a time; each must turn
# tests/pre-wipe-inventory.sh red.
# SC2016: each mutation target is literal source text, not an expansion.
# shellcheck disable=SC2016
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
script=$repo_dir/scripts/pre-wipe-inventory.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

expect_caught() { # <description> <old> <new>
  local copy=$work/pre-wipe-inventory.sh
  OLD=$2 NEW=$3 python3 - "$script" "$copy" <<'PY'
import os, sys
text = open(sys.argv[1]).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(sys.argv[2], "w").write(text.replace(old, new))
PY
  if "$repo_dir/tests/pre-wipe-inventory.sh" "$copy" >/dev/null 2>&1; then
    echo "MISSED: $1"; failures=$((failures + 1))
  else
    echo "caught: $1"
  fi
}

"$repo_dir/tests/pre-wipe-inventory.sh" >/dev/null || { echo "FAIL: the unmutated script fails its tests"; exit 1; }
expect_caught 'tracked changes are not reported' '((count > 0)) && echo "tracked uncommitted changes: $count"' ':'
expect_caught 'stashes are not reported' '((count > 0)) && echo "stashes: $count"' ':'
expect_caught 'a branch ahead of its upstream is not reported' '((count > 0)) && echo "branch \`${ref#refs/heads/}\`: $count commit(s) ahead' 'false && echo "branch \`${ref#refs/heads/}\`: $count commit(s) ahead'
expect_caught 'a branch with no upstream is not reported' '((count > 0)) && echo "branch \`${ref#refs/heads/}\`: no upstream' 'false && echo "branch \`${ref#refs/heads/}\`: no upstream'
expect_caught 'a repository with no remote is not reported' "&& echo 'no remote'" '&& :'
expect_caught 'repositories directly under HOME are not searched' 'done < <(home_repos)' 'done < <(:)'
expect_caught 'clean repositories are listed' 'if [[ -z $findings ]]; then
    repo_clean' 'if [[ -z $findings && 1 == 2 ]]; then
    repo_clean'
expect_caught 'clean repositories are left out of the summary' 'section_items[current]=$((section_items[current] + repo_clean))' ':'
expect_caught 'a credential file is opened and printed' 'listing=$(ls -A "$1" 2>/dev/null)' 'listing=$(cat "$1"/* 2>/dev/null)'
expect_caught 'git status may rewrite the index' 'git_ro() { GIT_OPTIONAL_LOCKS=0 git' 'git_ro() { git'
expect_caught 'the script writes a file' 'export HOMEBREW_NO_AUTO_UPDATE=1' ': >"$HOME/.inventory-ran"; export HOMEBREW_NO_AUTO_UPDATE=1'
expect_caught 'a missing tool is called anyway' 'have() { command -v "$1" >/dev/null 2>&1; }' 'have() { true; }'
expect_caught 'a probe calls a tool without checking for it' 'have brew && brew_prefix=$(brew --prefix 2>/dev/null)' 'brew_prefix=$(brew --prefix)'
expect_caught 'the run exits non-zero' '
exit 0
' '
exit 1
'
expect_caught 'the report has no summary' "printf '\n## Summary" "printf '\n## Totals"
((failures == 0)) && echo "every mutant is caught"
