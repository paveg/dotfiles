#!/usr/bin/env bash
# Break one condition of the git files at a time and require the checks in
# tests/git.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. Every check has a mutant here except setup-repositories,
# which guards this harness, and the no-profile checks, whose subject is git
# ignoring a missing include. Mutants of profiles/work.example/ stand for a
# work profile written the wrong way.
# Env: GIT_BIN is passed through to tests/git.sh.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0

expect_pass() {
  local out
  if out=$("$repo_dir/tests/git.sh" 2>&1); then
    echo "pass: the files as committed"
  else
    echo "FAIL: the files as committed should pass"
    grep '^FAIL' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

# <file> is relative to a copy holding home/ and profile/ (the work profile).
expect_caught() { # <check>... <description> <file> <old> <new>
  local checks=$1 description=$2 file=$3 old=$4 new=$5 dir out check missing
  dir=$(mktemp -d "$work_dir/mutant.XXXX")
  cp -R "$repo_dir/home" "$dir/home"
  cp -R "$repo_dir/profiles/work.example" "$dir/profile"
  OLD=$old NEW=$new python3 - "$dir/$file" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
  out=$("$repo_dir/tests/git.sh" "$dir/home" "$dir/profile" 2>&1) || true
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

config=home/.config/git/config
include=profile/git/include.gitconfig
work_include=$'[include]\n  path = ~/.config/dots-work/git/include.gitconfig\n'
personal_include=$'[include]\n  path = ~/.config/git/personal.gitconfig\n'

expect_pass

expect_caught 'personal-repo-name personal-repo-email personal-worktree-in-org-dir-name
  outside-any-repo-name outside-any-repo-email no-profile-org-repo-name no-profile-org-repo-email' \
  'the personal identity is never included' \
  "$config" "$personal_include" ''

expect_caught personal-identity-set 'the personal identity has no email' \
  home/.config/git/personal.gitconfig '  email = pavegy@gmail.com' ''

expect_caught work-identity-set 'the example work identity is the personal one' \
  profile/git/work.gitconfig 'email = work@example.com' 'email = pavegy@gmail.com'

expect_caught 'work-repo-name work-repo-email work-worktree-inside-name work-worktree-inside-email
  work-worktree-outside-name work-worktree-outside-email' \
  'the work profile is never included' \
  "$config" "$work_include" ''

expect_caught 'work-repo-email work-worktree-inside-email work-worktree-outside-email' \
  'the work profile is included before the personal identity, which then wins' \
  "$config" "$personal_include$work_include" "$work_include$personal_include"

expect_caught 'work-repo-email work-worktree-outside-email' \
  'the work profile is included from a path the profile does not use' \
  "$config" '~/.config/dots-work/git/include.gitconfig' '~/.config/dots-work/include.gitconfig'

expect_caught 'personal-repo-email personal-worktree-in-org-dir-email outside-any-repo-email' \
  'the work identity is included for every repository' \
  "$config" '~/.config/dots-work/git/include.gitconfig' '~/.config/dots-work/git/work.gitconfig'

expect_caught 'work-repo-email work-worktree-inside-email work-worktree-outside-email' \
  'the org directory pattern has no trailing slash, so it matches no repository below it' \
  "$include" 'example-org/"]' 'example-org"]'

expect_caught 'work-worktree-inside-email work-worktree-outside-email' \
  'the condition matches only a main checkout'"'"'s .git, which no linked worktree has as its gitdir' \
  "$include" '"gitdir:~/repos/github.com/example-org/"' '"gitdir:~/repos/github.com/example-org/*/.git"'

expect_caught 'work-repo-email work-worktree-inside-email work-worktree-outside-email' \
  'the condition is a branch name, which says nothing about where a repository lives' \
  "$include" '"gitdir:~/repos/github.com/example-org/"' '"onbranch:example-org/"'

expect_caught ignore-claude-worktrees 'the global ignore leaves agent worktrees in git status' \
  home/.config/git/ignore $'.claude/worktrees/\n' ''

expect_caught ignore-claude-worktrees 'the global ignore is read from somewhere else' \
  "$config" 'excludesFile = ~/.config/git/ignore' 'excludesFile = ~/.config/git/ignore.missing'

expect_caught ghq-root 'ghq clones somewhere other than ~/repos' \
  "$config" 'root = ~/repos' 'root = ~/ghq'

if ((failures > 0)); then
  echo "$failures mutation check(s) failed"
  exit 1
fi
echo "every mutant is caught"
