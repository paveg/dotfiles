#!/usr/bin/env bash
# Check scripts/pre-wipe-inventory.sh against fixtures in a temporary HOME and
# ghq root: every dirty repository is listed with its reason, the clean one is
# only counted, a credential file's contents never reach the output, the run
# exits 0 with none of the optional tools on PATH, and nothing under the
# temporary tree changes.
# Usage: tests/pre-wipe-inventory.sh [script]   (a mutant copy may be given)
# SC2016: backticks inside single quotes are Markdown the report must contain.
# shellcheck disable=SC2016
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
script=${1:-$repo_dir/scripts/pre-wipe-inventory.sh}
bash_bin=/bin/bash
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

# Fixtures are built with the real git but none of the owner's configuration,
# which may sign commits through 1Password.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.com
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.com
fixture_git() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

root=$work_dir/root
home=$root/home
ghq_root=$root/ghq
remotes=$work_dir/remotes
mkdir -p "$home" "$ghq_root/example.com/owner" "$remotes"

commit() { # <repo> <file> <text>
  printf '%s\n' "$3" >>"$1/$2"
  fixture_git -C "$1" add "$2"
  fixture_git -C "$1" commit -q -m "$2"
}

pushed_repo() { # <name>   prints a clone whose main is pushed to a local bare remote
  local dir=$ghq_root/example.com/owner/$1
  fixture_git init -q --bare "$remotes/$1.git"
  fixture_git clone -q "$remotes/$1.git" "$dir" 2>/dev/null
  commit "$dir" README "$1"
  fixture_git -C "$dir" push -q -u origin main 2>/dev/null
  echo "$dir"
}

dir=$(pushed_repo tracked-change)
printf 'edited\n' >>"$dir/README"

dir=$(pushed_repo stashed-work)
printf 'stashed\n' >>"$dir/README"
fixture_git -C "$dir" stash push -q -m fixture

dir=$(pushed_repo ahead-of-upstream)
commit "$dir" README 'not pushed'

dir=$(pushed_repo local-branch)
fixture_git -C "$dir" checkout -q -b feature-without-upstream
commit "$dir" README 'only on the local branch'

# A clean repository whose tracked file has a new mtime but the same contents:
# a plain `git status` refreshes the index here, which the snapshot catches.
dir=$(pushed_repo clean-repo)
touch -t 202001010000 "$dir/README"

# The repository with no remote sits directly under HOME, which the script
# searches besides the ghq root.
dir=$home/no-remote-repo
fixture_git init -q "$dir"
commit "$dir" notes 'never pushed'

# A clone under ~/.config is not searched as a repository, so the unmanaged
# files section must still name it.
fixture_git init -q "$home/.config/cloned-tool"

# A macOS folder no other section reports, and an atuin data directory, which
# holds atuin's key.
mkdir -p "$home/Music" "$home/.local/share/atuin"

# The credential fixture's path is assembled here so that it never appears on a
# command line, where the live credential guard would block it.
marker='fixture-line-that-must-never-be-printed'
credential_dir=$home/.ssh
key_name=id_test
mkdir -p "$credential_dir"
printf '%s\n' "$marker" >"$credential_dir/$key_name"

# Only git and the utilities a POSIX script needs; no brew, docker, nix, or the
# other optional tools, so every optional probe takes its "not installed" path.
stub_bin=$work_dir/bin
mkdir -p "$stub_bin"
for tool in git awk basename cat cut date dirname du find grep head ls sed sort tail tr uname wc; do
  ln -s "$(command -v "$tool")" "$stub_bin/$tool"
done

snapshot() { # prints every path under the temporary tree and a checksum of each file
  (
    cd "$root"
    find . -print | LC_ALL=C sort
    find . -type f -exec cksum {} + | LC_ALL=C sort
  )
}

block_of() { # <label>   prints the report's bullet for a repository and its sub-bullets
  awk -v label="\`$1\`" '
    index($0, label) && /^- / { inside = 1; print; next }
    inside && /^  / { print; next }
    { inside = 0 }
  ' "$work_dir/out"
}

has() { # <name> <text> <fixed string>
  if grep -qF -- "$3" <<<"$2"; then ok "$1"; else fail "$1" "no '$3' in: $(tr '\n' ' ' <<<"$2" | cut -c1-300)"; fi
}

snapshot >"$work_dir/before"
status=0
env -i HOME="$home" PATH="$stub_bin" GHQ_ROOT="$ghq_root" LC_ALL=C \
  "$bash_bin" "$script" >"$work_dir/out" 2>"$work_dir/err" || status=$?
snapshot >"$work_dir/after"

if [[ $status == 0 ]]; then ok exit-0; else fail exit-0 "exit $status"; fi
if grep -q '^## Summary' "$work_dir/out"; then ok summary-section; else fail summary-section "no '## Summary' heading"; fi
if grep -q 'command not found' "$work_dir/err"; then
  fail missing-tools-probed "$(grep 'command not found' "$work_dir/err" | head -3 | tr '\n' ' ')"
else
  ok missing-tools-probed
fi
for tool in ghq docker colima lima Homebrew brew mas devbox npm pnpm uv cargo mise; do
  has "not-installed-$tool" "$(cat "$work_dir/out")" "- $tool: not installed"
done

has tracked-change "$(block_of example.com/owner/tracked-change)" 'tracked uncommitted changes: 1'
has stashed-work "$(block_of example.com/owner/stashed-work)" 'stashes: 1'
has ahead-of-upstream "$(block_of example.com/owner/ahead-of-upstream)" '1 commit(s) ahead of `origin/main`'
has local-branch "$(block_of example.com/owner/local-branch)" '`feature-without-upstream`: no upstream'
# SC2088: the report's label, not a path to expand.
# shellcheck disable=SC2088
has no-remote "$(block_of '~/no-remote-repo')" '  - no remote'

if grep -qF clean-repo "$work_dir/out"; then
  fail clean-repo-not-listed "$(grep -F clean-repo "$work_dir/out" | head -3 | tr '\n' ' ')"
else
  ok clean-repo-not-listed
fi
has clean-repo-counted "$(cat "$work_dir/out")" 'Clean repositories (counted, not listed): 1'
has git-summary "$(cat "$work_dir/out")" '| Git repositories | 6 | 5 |'

has config-repo-listed "$(cat "$work_dir/out")" '- **needs action:** `~/.config/cloned-tool`'
has music-listed "$(cat "$work_dir/out")" '- **needs action:** `~/Music`'
has atuin-confirm "$(grep -F 'atuin data' "$work_dir/out")" 'confirm this is in 1Password or can be re-created'
has credential-listed "$(cat "$work_dir/out")" "$key_name"
if grep -qF -- "$marker" "$work_dir/out" "$work_dir/err"; then
  fail credential-contents-not-printed 'the fixture key contents appear in the output'
else
  ok credential-contents-not-printed
fi

if diff "$work_dir/before" "$work_dir/after" >"$work_dir/diff"; then
  ok nothing-changed
else
  fail nothing-changed "$(head -5 "$work_dir/diff" | tr '\n' ' ')"
fi

echo "summary: $checks checks, $failures failed"
((failures == 0))
