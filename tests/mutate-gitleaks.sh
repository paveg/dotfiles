#!/usr/bin/env bash
# Show that tests/gitleaks.sh refuses a secret wherever the history of the
# checked-out commit adds it, and passes one that only another branch holds.
# Each case is a scratch repository; the merge cases end, as a pull request run
# does, on a merge of the feature branch into main.
# Usage: tests/mutate-gitleaks.sh   (needs gitleaks on PATH)
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
check=$repo_dir/tests/gitleaks.sh
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
cases=0
failures=0

# A fake GitHub token, built at run time so that no tracked file holds one.
fake_token="ghp_$(head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-36)"

g() { git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }

scratch() { # prints a fresh repository with one commit on main
  local dir
  dir=$(mktemp -d "$work_dir/case.XXXX")
  g -C "$dir" init -q -b main
  echo base >"$dir/README"
  g -C "$dir" add README
  g -C "$dir" commit -qm base
  echo "$dir"
}

merge_into_main() { # <repo>: the merge commit a pull request run checks out
  g -C "$1" checkout -q --detach main
  g -C "$1" merge -q --no-ff --no-edit feature
}

# A refusal counts only when gitleaks reports the leak, so a scan that crashes
# does not pass a fail case; a pass needs gitleaks' own clean verdict.
expect() { # <pass|fail> <description> <repo>
  cases=$((cases + 1))
  if "$check" "$3" >"$work_dir/out" 2>&1; then
    if grep -q 'no leaks found' "$work_dir/out"; then got=pass; else got='pass without a verdict'; fi
  elif grep -q 'leaks found: [1-9]' "$work_dir/out"; then
    got=fail
  else
    got='fail without a leak'
  fi
  if grep -qF -- "$fake_token" "$work_dir/out"; then got="$got, with the secret printed"; fi
  if [[ $got == "$1" ]]; then
    echo "ok: $2 ($got)"
  else
    failures=$((failures + 1))
    echo "FAIL: $2 should $1, got $got"
    sed "s/$fake_token/<fake token>/g; s/^/  /" "$work_dir/out"
  fi
}

dir=$(scratch)
expect pass 'a history with no secret' "$dir"

dir=$(scratch)
echo "token=$fake_token" >"$dir/conf.txt"
g -C "$dir" add conf.txt
g -C "$dir" commit -qm 'add conf'
expect fail 'a secret added by an ordinary commit' "$dir"

dir=$(scratch)
g -C "$dir" checkout -qb side
echo "token=$fake_token" >"$dir/conf.txt"
g -C "$dir" add conf.txt
g -C "$dir" commit -qm 'add conf'
g -C "$dir" checkout -q main
expect pass 'a secret that only a branch not merged into HEAD holds' "$dir"

dir=$(scratch)
g -C "$dir" checkout -qb feature
echo feature >"$dir/feature.txt"
g -C "$dir" add feature.txt
g -C "$dir" commit -qm feature
g -C "$dir" checkout -q main
echo main >"$dir/main.txt"
g -C "$dir" add main.txt
g -C "$dir" commit -qm main
g -C "$dir" checkout -q feature
g -C "$dir" merge -q --no-commit --no-ff main >/dev/null 2>&1
echo "token=$fake_token" >"$dir/conf.txt"
g -C "$dir" add conf.txt
g -C "$dir" commit -qm 'Merge main into feature'
merge_into_main "$dir"
expect fail 'a new file that only a merge on the branch adds' "$dir"

dir=$(scratch)
echo line=base >"$dir/conf.txt"
g -C "$dir" add conf.txt
g -C "$dir" commit -qm conf
g -C "$dir" checkout -qb feature
echo line=feature >"$dir/conf.txt"
g -C "$dir" commit -qam feature
g -C "$dir" checkout -q main
echo line=main >"$dir/conf.txt"
g -C "$dir" commit -qam main
g -C "$dir" checkout -q feature
g -C "$dir" merge -q main >/dev/null 2>&1 || true
echo "token=$fake_token" >"$dir/conf.txt"
g -C "$dir" add conf.txt
g -C "$dir" commit -qm 'Merge main into feature'
merge_into_main "$dir"
expect fail 'a secret typed into the resolution of a merge conflict' "$dir"

dir=$(scratch)
g -C "$dir" checkout -qb feature
echo "token=$fake_token" >"$dir/conf.txt"
g -C "$dir" add conf.txt
g -C "$dir" commit -qm 'add conf'
g -C "$dir" rm -q conf.txt
g -C "$dir" commit -qm 'remove conf'
merge_into_main "$dir"
expect fail 'a secret added and removed again on a branch merged into HEAD' "$dir"

echo "summary: $cases cases, $failures failed"
if ((failures > 0)); then exit 1; fi
