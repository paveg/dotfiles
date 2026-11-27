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
work_dir=$(cd "$(mktemp -d)" && pwd -P)
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
fixture_git() { git -c init.defaultBranch=main -c commit.gpgsign=false -c protocol.file.allow=always "$@"; }

root=$work_dir/root
home=$root/home
ghq_root=$root/ghq
second_root=$root/ghq-second
remotes=$work_dir/remotes
mkdir -p "$home" "$ghq_root/example.com/owner" "$second_root/example.com/owner" "$remotes"

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

# A clone under ~/.config with no commits: counted as a clean repository, and
# still named by the unmanaged files section.
fixture_git init -q "$home/.config/cloned-tool"

dir=$(pushed_repo detached-head)
fixture_git -C "$dir" checkout -q --detach
commit "$dir" README 'only on a detached HEAD'

dir=$(pushed_repo tag-only)
commit "$dir" README 'only on a tag'
fixture_git -C "$dir" tag -a local-tag -m 'local tag'
fixture_git -C "$dir" reset -q --hard origin/main

dir=$(pushed_repo linked-detached)
fixture_git -C "$dir" worktree add -q --detach "$home/wt/linked-detached"
commit "$home/wt/linked-detached" README 'only on the linked worktree'

mkdir -p "$home/.cache/gitdirs"
fixture_git init -q --separate-git-dir="$home/.cache/gitdirs/gitfile.git" "$ghq_root/example.com/owner/gitfile"
commit "$ghq_root/example.com/owner/gitfile" notes 'repository with a .git file'

# Bare repositories that hold the only copy; a worktree of one has an uncommitted change.
for name in bare-only bare-alone; do
  fixture_git init -q --bare "$ghq_root/example.com/owner/$name.git"
  fixture_git clone -q "$ghq_root/example.com/owner/$name.git" "$work_dir/$name-clone" 2>/dev/null
  commit "$work_dir/$name-clone" README 'only in the bare repository'
  fixture_git -C "$work_dir/$name-clone" push -q origin main 2>/dev/null
done
fixture_git --git-dir="$ghq_root/example.com/owner/bare-only.git" worktree add -q "$ghq_root/example.com/owner/bare-worktree" main 2>/dev/null
printf 'uncommitted\n' >>"$ghq_root/example.com/owner/bare-worktree/README"

for dir in "$ghq_root/gitlab.com/group/sub1/sub2/deep-repo" "$home/work/work-repo" \
  "$home/.local/share/chezmoi" "$second_root/example.com/owner/second-root-repo"; do
  fixture_git init -q "$dir"
  commit "$dir" notes 'never pushed'
done

# Submodules whose own repository holds the unsaved work.
fixture_git init -q --bare "$remotes/library.git"
fixture_git clone -q "$remotes/library.git" "$work_dir/library" 2>/dev/null
commit "$work_dir/library" lib 'v1'
fixture_git -C "$work_dir/library" push -q -u origin main 2>/dev/null
for name in sub-untracked sub-unpushed sub-stash; do
  dir=$(pushed_repo "$name")
  fixture_git -C "$dir" submodule -q add "$remotes/library.git" sub 2>/dev/null
  fixture_git -C "$dir" commit -q -m 'add sub'
  fixture_git -C "$dir" push -q 2>/dev/null
done
printf 'new\n' >"$ghq_root/example.com/owner/sub-untracked/sub/untracked-file"
commit "$ghq_root/example.com/owner/sub-unpushed/sub" lib 'only in the submodule'
printf 'stashed\n' >>"$ghq_root/example.com/owner/sub-stash/sub/lib"
fixture_git -C "$ghq_root/example.com/owner/sub-stash/sub" stash push -q -m fixture

# A `.git` git cannot read must be listed, not counted as clean.
mkdir -p "$home/broken-repo/.git"

# A clean filter the repository configures; `git status` runs it on a file
# whose mtime changed, and the filter leaves a marker the snapshot catches.
filter_marker=$root/filter-ran
filter_script=$work_dir/filter
printf '#!/bin/sh\necho ran >>%s\nexec /bin/cat\n' "$filter_marker" >"$filter_script"
chmod +x "$filter_script"
dir=$(pushed_repo filter-repo)
printf '* filter=probe\n' >"$dir/.gitattributes"
fixture_git -C "$dir" add .gitattributes
fixture_git -C "$dir" commit -q -m attributes
fixture_git -C "$dir" push -q 2>/dev/null
fixture_git -C "$dir" config filter.probe.clean "$filter_script"
touch -t 202001010000 "$dir/README"

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
# Env files outside the ghq root: in a repository under ~ and in a linked worktree.
env_name=.env.local
printf '%s\n' "$marker" >"$home/work/work-repo/$env_name"
printf '%s\n' "$marker" >"$home/wt/linked-detached/$env_name"

# Only git and the utilities a POSIX script needs; no brew, docker, nix, or the
# other optional tools, so every optional probe takes its "not installed" path.
stub_bin=$work_dir/bin
mkdir -p "$stub_bin"
for tool in git awk basename cat cut date dirname du find grep head ls sed sort tail tr uname wc; do
  ln -s "$(command -v "$tool")" "$stub_bin/$tool"
done

# A second run puts package managers on PATH as stubs that log every call. The
# script must read the files each one keeps instead of running it, apart from
# `npm root -g`, `uv tool dir`, and `ghq root --all`, which print a directory.
tools_bin=$work_dir/tools
calls=$work_dir/calls
brew_prefix=$root/homebrew
mkdir -p "$tools_bin" "$brew_prefix/bin"
stub() { # <path> [<arguments the stub answers> <answer>]
  printf '#!/bin/sh\n[ "$*" = "%s" ] && [ -n "%s" ] && { echo "%s"; exit 0; }\necho "${0##*/} $*" >>%s\n' "${2:-}" "${2:-}" "${3:-}" "$calls" >"$1"
  chmod +x "$1"
}
stub "$brew_prefix/bin/brew"
for tool in devbox mise cargo pnpm colima limactl nix; do stub "$tools_bin/$tool"; done
stub "$tools_bin/npm" 'root -g' "$root/npm-global/lib/node_modules"
stub "$tools_bin/uv" 'tool dir' "$root/uv-tools"
stub "$tools_bin/ghq" 'root --all' "$ghq_root
$second_root"
for dir in Cellar/fixture-formula/1.0 Cellar/fzf/0.1 Cellar/fixture-dependency/2.0 Caskroom/fixture-cask/3.0; do
  mkdir -p "$brew_prefix/$dir"
done
printf '{\n  "installed_on_request": true\n}\n' | tee "$brew_prefix/Cellar/fzf/0.1/INSTALL_RECEIPT.json" >"$brew_prefix/Cellar/fixture-formula/1.0/INSTALL_RECEIPT.json"
printf '{\n  "installed_on_request": false\n}\n' >"$brew_prefix/Cellar/fixture-dependency/2.0/INSTALL_RECEIPT.json"
mkdir -p "$home/.local/share/devbox/global/default" "$root/npm-global/lib/node_modules/fixture-npm" \
  "$root/npm-global/lib/node_modules/@scope/fixture-scoped" "$root/pnpm/global/5/node_modules/fixture-pnpm" \
  "$root/uv-tools/fixture-uv" "$home/.cargo" "$home/.local/share/mise/installs/fixture-tool/1.0" \
  "$home/.colima/_lima/colima" "$home/.lima/fixture-vm"
printf '{\n  "packages": [\n    "fixture-devbox@latest"\n  ]\n}\n' >"$home/.local/share/devbox/global/default/devbox.json"
printf '{"installs":{"fixture-crate 1.2.3 (registry+https://github.com/rust-lang/crates.io-index)":{"bins":["fixture"]}}}\n' >"$home/.cargo/.crates2.json"
ln -s 1.0 "$home/.local/share/mise/installs/fixture-tool/latest"
touch "$home/.colima/_lima/colima/lima.yaml" "$home/.lima/fixture-vm/lima.yaml"

snapshot() { # prints every path under the temporary tree and a checksum of each file
  (
    cd "$root"
    find . -print | LC_ALL=C sort
    find . -type f -exec cksum {} + | LC_ALL=C sort
  )
}

block_of() { # <label> [report]   prints the report's bullet for a repository and its sub-bullets
  awk -v label="\`$1\`" '
    index($0, label) && /^- / { inside = 1; print; next }
    inside && /^  / { print; next }
    { inside = 0 }
  ' "${2:-$work_dir/out}"
}

has() { # <name> <text> <fixed string>
  if grep -qF -- "$3" <<<"$2"; then ok "$1"; else fail "$1" "no '$3' in: $(tr '\n' ' ' <<<"$2" | cut -c1-300)"; fi
}

snapshot >"$work_dir/before"
status=0
env -i HOME="$home" PATH="$stub_bin" GHQ_ROOT="$ghq_root:$second_root" LC_ALL=C \
  "$bash_bin" "$script" >"$work_dir/out" 2>"$work_dir/err" || status=$?
env -i HOME="$home" PATH="$tools_bin:$brew_prefix/bin:$stub_bin" PNPM_HOME="$root/pnpm" LC_ALL=C \
  "$bash_bin" "$script" >"$work_dir/out-tools" 2>"$work_dir/err-tools" || status=$?
snapshot >"$work_dir/after"

if [[ $status == 0 ]]; then ok exit-0; else fail exit-0 "exit $status"; fi
if grep -q '^## Summary' "$work_dir/out"; then ok summary-section; else fail summary-section "no '## Summary' heading"; fi
if grep -q 'command not found' "$work_dir/err"; then
  fail missing-tools-probed "$(grep 'command not found' "$work_dir/err" | head -3 | tr '\n' ' ')"
else
  ok missing-tools-probed
fi
for tool in ghq docker Homebrew brew mas npm uv; do
  has "not-installed-$tool" "$(cat "$work_dir/out")" "- $tool: not installed"
done

if [[ -s $calls ]]; then fail tools-not-run "$(head -5 "$calls" | tr '\n' ' ')"; else ok tools-not-run; fi
software=$(sed -n '/^## Installed software/,/^## Files no dotfiles/p' "$work_dir/out-tools")
for item in '`fixture-formula`' '`fixture-cask`' '`fixture-devbox@latest`' '`fixture-npm`' '`@scope/fixture-scoped`' \
  '`fixture-pnpm`' '`fixture-uv`' '`fixture-crate 1.2.3`' '`fixture-tool 1.0`'; do
  has "software-read-$item" "$software" "**needs action:** $item"
done
has nix-package-marked "$software" '`fzf` (in `nix/packages.nix`)'
if grep -qF fixture-dependency <<<"$software"; then fail formula-dependency-left-out 'a dependency is listed'; else ok formula-dependency-left-out; fi
if grep -qF '`fixture-tool latest`' <<<"$software"; then fail mise-alias-left-out 'a version alias is listed'; else ok mise-alias-left-out; fi
vms=$(sed -n '/^## Containers and VMs/,/^## Local databases/p' "$work_dir/out-tools")
has colima-vm-read "$vms" 'lima VM `colima`'
has lima-vm-read "$vms" 'lima VM `fixture-vm`'
has ghq-root-all "$(block_of example.com/owner/second-root-repo "$work_dir/out-tools")" '  - no remote'

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
has clean-repo-counted "$(cat "$work_dir/out")" 'Clean repositories (counted, not listed): 5'
has git-summary "$(cat "$work_dir/out")" '| Git repositories | 25 | 20 |'

has detached-head "$(block_of example.com/owner/detached-head)" 'commits on no remote ref: 1'
has detached-head-no-branch "$(block_of example.com/owner/detached-head)" 'on no branch (a detached HEAD or only a tag): 1'
has tag-only "$(block_of example.com/owner/tag-only)" 'commits on no remote ref: 1'
has linked-worktree-head "$(block_of example.com/owner/linked-detached)" 'commits on no remote ref: 1'
has git-file-repo "$(block_of example.com/owner/gitfile)" 'commits on no remote ref: 1'
has bare-only-copy "$(block_of example.com/owner/bare-only.git)" '  - no remote'
has bare-without-worktree "$(block_of example.com/owner/bare-alone.git)" '  - no remote'
has bare-worktree "$(block_of example.com/owner/bare-only.git)" 'example.com/owner/bare-worktree`: 1 tracked uncommitted change(s)'
has deep-repo "$(block_of gitlab.com/group/sub1/sub2/deep-repo)" '  - no remote'
# shellcheck disable=SC2088
has work-repo "$(block_of '~/work/work-repo')" '  - no remote'
# shellcheck disable=SC2088
has chezmoi-source "$(block_of '~/.local/share/chezmoi')" '  - no remote'
has second-ghq-root "$(block_of example.com/owner/second-root-repo)" '  - no remote'
has submodule-untracked "$(block_of example.com/owner/sub-untracked/sub)" 'untracked files: 1'
has submodule-unpushed "$(block_of example.com/owner/sub-unpushed/sub)" 'commits on no remote ref: 1'
has submodule-stash "$(block_of example.com/owner/sub-stash/sub)" 'stashes: 1'
# shellcheck disable=SC2088
has unreadable-repo "$(block_of '~/broken-repo')" 'git cannot read this repository'
if [[ -e $filter_marker ]]; then fail filter-not-run 'a repository clean filter ran'; else ok filter-not-run; fi

# shellcheck disable=SC2088
has next-step-bundle "$(block_of '~/no-remote-repo')" "next: \`git -C '$home/no-remote-repo' bundle create no-remote-repo.bundle --all\`"
has next-step-push "$(block_of example.com/owner/local-branch)" "next: \`git -C '$ghq_root/example.com/owner/local-branch' push origin feature-without-upstream\`"
has next-step-commit-first "$(block_of example.com/owner/tracked-change)" 'next: commit the uncommitted and untracked work'
has next-step-no-branch "$(block_of example.com/owner/detached-head)" 'put the commits on no branch on a branch or tag'

has config-repo-listed "$(cat "$work_dir/out")" '- **needs action:** `~/.config/cloned-tool`'
has music-listed "$(cat "$work_dir/out")" '- **needs action:** `~/Music`'
has atuin-confirm "$(grep -F 'atuin data' "$work_dir/out")" 'confirm this is in 1Password or can be re-created'
has credential-listed "$(cat "$work_dir/out")" "$key_name"
credentials=$(sed -n '/^## Credentials/,/^## Containers/p' "$work_dir/out")
# shellcheck disable=SC2088
has env-outside-ghq-root "$credentials" "\`~/work/work-repo/$env_name\`"
# shellcheck disable=SC2088
has env-in-linked-worktree "$credentials" "\`~/wt/linked-detached/$env_name\`"
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
