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
# Everything below, fixtures included, runs on a temporary HOME, the system PATH
# plus a link to git, and no XDG_* variable: an inherited XDG_CONFIG_HOME once
# pointed a run at the real HOME's files.
if [[ -z ${INVENTORY_TEST_DIR:-} ]]; then
  work_dir=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$work_dir/needed" "$work_dir/host" "$work_dir/root/home"
  ln -s "$(command -v git)" "$work_dir/needed/git"
  # Off PATH: the host's chezmoi, if any, which the chezmoi check below offers the script.
  if command -v chezmoi >/dev/null; then ln -s "$(command -v chezmoi)" "$work_dir/host/chezmoi"; fi
  exec env -i INVENTORY_TEST_DIR="$work_dir" HOME="$work_dir/root/home" PATH="$work_dir/needed:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$bash_bin" "$0" "$script"
fi
work_dir=$INVENTORY_TEST_DIR
if env | grep -q '^XDG_' || [[ $HOME != "$work_dir/root/home" ]]; then
  echo "FAIL: the tests see an XDG_* variable or a HOME other than $work_dir/root/home"
  exit 1
fi
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

# A commit only a ref outside heads and tags holds, made without touching HEAD,
# so no reflog holds it; and a commit only the reflog holds.
dir=$(pushed_repo wip-ref)
fixture_git -C "$dir" update-ref refs/wip/x "$(fixture_git -C "$dir" commit-tree -p HEAD -m 'only on refs/wip/x' 'HEAD^{tree}')"
dir=$(pushed_repo reflog-only)
commit "$dir" README 'only in the reflog'
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

# A chezmoi source, rooted in home/ by `.chezmoiroot`, whose hook and `output`
# template leave a marker and whose external fetches from a closed port when
# chezmoi reads it. The names in it mark two entries in HOME as managed.
chezmoi_source=$home/.local/share/chezmoi
hook_marker=$root/chezmoi-hook-ran
template_marker=$root/chezmoi-template-ran
mkdir -p "$chezmoi_source/home/dot_claude" "$home/.config/chezmoi" "$home/.claude"
printf 'home\n' >"$chezmoi_source/.chezmoiroot"
printf '[hooks.read-source-state.pre]\n    command = "/bin/sh"\n    args = ["-c", "echo ran >%s"]\n' "$hook_marker" >"$home/.config/chezmoi/chezmoi.toml"
printf '{{ output "/bin/sh" "-c" "echo ran >%s" }}\n' "$template_marker" >"$chezmoi_source/home/.chezmoiignore"
printf '[".fixture-external"]\n    type = "archive"\n    url = "http://127.0.0.1:9/fixture.tar.gz"\n' >"$chezmoi_source/home/.chezmoiexternal.toml"
printf 'managed\n' | tee "$chezmoi_source/home/dot_fixture-managed" "$chezmoi_source/home/dot_claude/private_fixture-settings.json.tmpl" \
  "$home/.fixture-managed" "$home/.claude/fixture-settings.json" "$home/.fixture-unmanaged" >/dev/null

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

# The credential fixtures' paths are assembled here so that they never appear on
# a command line, where the live credential guard would block them.
marker='fixture-line-that-must-never-be-printed'
memory=$home/.claude/projects/-fixture/memory
notes=$home/.local/share/agent-notes
# ~/.ssh is a symlink into the Claude Code memory, which --backup-paths reads.
credential_dir=$memory/ssh
key_name=id_test
mkdir -p "$credential_dir"
ln -s "$credential_dir" "$home/.ssh"
printf '%s\n' "$marker" >"$credential_dir/$key_name"
# Env files outside the ghq root: in a repository under ~ and in a linked worktree.
env_name=.env.local
printf '%s\n' "$marker" >"$home/work/work-repo/$env_name"
printf '%s\n' "$marker" >"$home/wt/linked-detached/$env_name"

# --backup-paths lists the files below Claude Code memory and the agent notes.
# Beside them sits one file for each way such a file is left out: a credential
# name, a FIFO, a second hard link (to a docker login), and a symlink out of the
# root. Documents, with key-named files, and Downloads are no backup root.
mkdir -p "$notes" "$home/Documents" "$home/Downloads" "$home/.docker"
printf 'memory\n' >"$memory/MEMORY.md"
printf 'memory\n' >"$memory/TOKEN-rotation.md"
mkfifo "$memory/fifo"
docker_login=$home/.docker/config.json
printf '%s\n' "$marker" >"$docker_login"
ln "$docker_login" "$memory/hardlinked.md"
ln -s "$home/Documents/report.txt" "$memory/outside.md"
# The agent notes are a repository with no remote.
fixture_git init -q "$notes"
commit "$notes" note.md note
printf '%s\n' "$marker" >"$notes/$env_name"
unicode_note="$notes/uni code ñ.md"
printf 'note\n' >"$unicode_note"
# A file name holding a newline and then the fixture key's path, which a
# newline-separated list would offer as a path of its own.
forged="$memory/forged"$'\n'"$home/.ssh/$key_name"
mkdir -p "${forged%/*}"
printf 'decoy\n' >"$forged"
ed_name=github_ed25519
p8_name=AuthKey_FIXTURE.p8
printf 'document\n' >"$home/Documents/report.txt"
printf '%s\n' "$marker" | tee "$home/Documents/$ed_name" "$home/Documents/$p8_name" >/dev/null
printf 'download\n' >"$home/Downloads/file.zip"
pem_name=server.pem
dir=$(pushed_repo ignored-files)
printf 'local-notes.md\ndata/\nbuild/\n%s\n' "$env_name" >"$dir/.gitignore"
fixture_git -C "$dir" add .gitignore
fixture_git -C "$dir" commit -q -m ignore
fixture_git -C "$dir" push -q 2>/dev/null
mkdir -p "$dir/data" "$dir/build"
printf 'notes\n' >"$dir/local-notes.md"
printf 'db\n' >"$dir/data/app.sqlite"
printf '%s\n' "$marker" >"$dir/data/$pem_name"
printf '%s\n' "$marker" >"$dir/$env_name"
printf 'output\n' >"$dir/build/output.bin"
unicode_repo="$ghq_root/example.com/owner/uni code ñ"
fixture_git init -q "$unicode_repo"
printf 'notes.txt\n' >"$unicode_repo/.gitignore"
commit "$unicode_repo" .gitignore 'ignore notes'
printf 'notes\n' >"$unicode_repo/notes.txt"
# A repository whose ignored files sit in a credential location.
gnupg_dir=$home/.gnupg
fixture_git init -q "$gnupg_dir"
printf '*\n' >"$gnupg_dir/.gitignore"
commit "$gnupg_dir" .gitignore '!.gitignore'
printf '%s\n' "$marker" >"$gnupg_dir/pubring.kbx"

# Only git and the utilities a POSIX script needs; no brew, docker, nix, or the
# other optional tools, so every optional probe takes its "not installed" path.
stub_bin=$work_dir/bin
posix_tools=(awk basename cat cut date dirname du find grep head ls realpath sed sort tail tr uname wc)
mkdir -p "$stub_bin"
for tool in git "${posix_tools[@]}"; do
  ln -s "$(command -v "$tool")" "$stub_bin/$tool"
done

# A second run puts package managers on PATH as stubs that log every call. The
# script must read the files each one keeps instead of running it, apart from
# `uv tool dir` and `ghq root --all`, which print a directory.
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
# chezmoi is the host's own where it has one, so that a run of it shows as a
# marker or a new file in HOME; elsewhere a stub logs the call.
if [[ -e $work_dir/host/chezmoi ]]; then ln -s "$work_dir/host/chezmoi" "$tools_bin/chezmoi"; else stub "$tools_bin/chezmoi"; fi
stub "$tools_bin/npm"
stub "$tools_bin/uv" 'tool dir' "$root/uv-tools"
stub "$tools_bin/ghq" 'root --all' "$ghq_root
$second_root"
for dir in Cellar/fixture-formula/1.0 Cellar/fzf/0.1 Cellar/fixture-dependency/2.0 Caskroom/fixture-cask/3.0; do
  mkdir -p "$brew_prefix/$dir"
done
printf '{\n  "installed_on_request": true\n}\n' | tee "$brew_prefix/Cellar/fzf/0.1/INSTALL_RECEIPT.json" >"$brew_prefix/Cellar/fixture-formula/1.0/INSTALL_RECEIPT.json"
printf '{\n  "installed_on_request": false\n}\n' >"$brew_prefix/Cellar/fixture-dependency/2.0/INSTALL_RECEIPT.json"
mkdir -p "$home/.local/share/devbox/global/default" "$brew_prefix/lib/node_modules/fixture-npm" \
  "$brew_prefix/lib/node_modules/@scope/fixture-scoped" "$brew_prefix/lib/node_modules/npm" \
  "$home/.vite-plus/js_runtime/node/24.0.0/lib/node_modules/fixture-vite-plus" "$root/pnpm/global/5/node_modules/fixture-pnpm" \
  "$root/uv-tools/fixture-uv" "$home/.cargo" "$home/.local/share/mise/installs/fixture-tool/1.0" \
  "$home/.colima/_lima/colima" "$home/.lima/fixture-vm"
printf '{\n  "packages": [\n    "fixture-devbox@latest"\n  ]\n}\n' >"$home/.local/share/devbox/global/default/devbox.json"
printf '{"installs":{"fixture-crate 1.2.3 (registry+https://github.com/rust-lang/crates.io-index)":{"bins":["fixture"]}}}\n' >"$home/.cargo/.crates2.json"
ln -s 1.0 "$home/.local/share/mise/installs/fixture-tool/latest"
touch "$home/.colima/_lima/colima/lima.yaml" "$home/.lima/fixture-vm/lima.yaml"
# --backup-paths runs where git, ghq, and chezmoi only log a call: it needs none.
paths_bin=$work_dir/paths-bin
mkdir -p "$paths_bin"
for tool in "${posix_tools[@]}"; do ln -s "$(command -v "$tool")" "$paths_bin/$tool"; done
for tool in git ghq chezmoi; do stub "$paths_bin/$tool"; done
# Without realpath a symlinked credential location cannot be resolved.
no_realpath_bin=$work_dir/no-realpath-bin
mkdir -p "$no_realpath_bin"
for tool in "${posix_tools[@]}"; do [[ $tool == realpath ]] || ln -s "$(command -v "$tool")" "$no_realpath_bin/$tool"; done

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
env -i HOME="$home" PATH="$paths_bin" LC_ALL=C "$bash_bin" "$script" --backup-paths >"$work_dir/paths" 2>"$work_dir/err-paths" || status=$?
env -i HOME="$home" PATH="$no_realpath_bin" LC_ALL=C "$bash_bin" "$script" --backup-paths >"$work_dir/paths-no-realpath" 2>"$work_dir/err-no-realpath" || status=$?
snapshot >"$work_dir/after"
# ~/.ssh as a symlink into Documents instead, which is no backup root.
rm "$home/.ssh"
mkdir -p "$home/Documents/ssh"
printf '%s\n' "$marker" >"$home/Documents/ssh/$key_name"
ln -s "$home/Documents/ssh" "$home/.ssh"
env -i HOME="$home" PATH="$paths_bin" LC_ALL=C "$bash_bin" "$script" --backup-paths >"$work_dir/paths-ssh-documents" 2>/dev/null || status=$?

if [[ $status == 0 ]]; then ok exit-0; else fail exit-0 "exit $status"; fi
if grep -q '^## Summary' "$work_dir/out"; then ok summary-section; else fail summary-section "no '## Summary' heading"; fi
if grep -q 'command not found' "$work_dir/err"; then
  fail missing-tools-probed "$(grep 'command not found' "$work_dir/err" | head -3 | tr '\n' ' ')"
else
  ok missing-tools-probed
fi
for tool in ghq docker Homebrew brew mas uv; do
  has "not-installed-$tool" "$(cat "$work_dir/out")" "- $tool: not installed"
done

if [[ -s $calls ]]; then fail tools-not-run "$(head -5 "$calls" | tr '\n' ' ')"; else ok tools-not-run; fi
software=$(sed -n '/^## Installed software/,/^## Files no dotfiles/p' "$work_dir/out-tools")
for item in '`fixture-formula`' '`fixture-cask`' '`fixture-devbox@latest`' '`fixture-npm`' '`@scope/fixture-scoped`' \
  '`fixture-pnpm`' '`fixture-uv`' '`fixture-crate 1.2.3`' '`fixture-tool 1.0`'; do
  has "software-read-$item" "$software" "**needs action:** $item"
done
if grep -qF '`npm`' <<<"$software"; then fail npm-itself-left-out 'the npm bundled with Node is listed'; else ok npm-itself-left-out; fi
has npm-read-without-npm "$(sed -n '/^## Installed software/,/^## Files no dotfiles/p' "$work_dir/out")" '**needs action:** `fixture-vite-plus`'
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
has fetch-prune-first "$(cat "$work_dir/out")" 'run `git fetch --prune` in a repository first'
has clean-repo-counted "$(cat "$work_dir/out")" 'Clean repositories (counted, not listed): 5'
has git-summary "$(cat "$work_dir/out")" '| Git repositories | 30 | 25 |'

has detached-head "$(block_of example.com/owner/detached-head)" 'commits on no remote ref: 1'
has detached-head-no-branch "$(block_of example.com/owner/detached-head)" 'on no branch (a detached HEAD or only a tag): 1'
has tag-only "$(block_of example.com/owner/tag-only)" 'commits on no remote ref: 1'
has wip-ref "$(block_of example.com/owner/wip-ref)" 'commits on no remote ref: 1'
has reflog-only "$(block_of example.com/owner/reflog-only)" 'commits on no remote ref: 1'
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
if [[ -e $hook_marker || -e $template_marker ]]; then fail chezmoi-not-run 'a chezmoi hook or template ran'; else ok chezmoi-not-run; fi
unmanaged=$(sed -n '/^## Files no dotfiles manage/,/^## Large user folders/p' "$work_dir/out")
has chezmoi-unnamed-listed "$unmanaged" '`~/.fixture-unmanaged`'
if grep -qF '`~/.fixture-managed`' <<<"$unmanaged"; then fail chezmoi-source-name-managed 'a name in the chezmoi source is listed'; else ok chezmoi-source-name-managed; fi
if grep -qF 'fixture-settings.json' "$work_dir/out"; then fail chezmoi-attribute-name-managed 'a name with chezmoi attributes is listed'; else ok chezmoi-attribute-name-managed; fi

# shellcheck disable=SC2088
has next-step-bundle "$(block_of '~/no-remote-repo')" "next: \`git -C '$home/no-remote-repo' bundle create no-remote-repo.bundle --all\`"
has next-step-push "$(block_of example.com/owner/local-branch)" "next: \`git -C '$ghq_root/example.com/owner/local-branch' push origin feature-without-upstream\`"
has next-step-commit-first "$(block_of example.com/owner/tracked-change)" 'next: commit the uncommitted and untracked work'
has next-step-no-branch "$(block_of example.com/owner/detached-head)" 'put the commits on no branch on a branch or tag'

has config-repo-listed "$(cat "$work_dir/out")" '- **needs action:** `~/.config/cloned-tool`'
# shellcheck disable=SC2088
has notes-repo-unsaved "$(block_of '~/.local/share/agent-notes')" 'a git repository with unsaved work'
# shellcheck disable=SC2088
has notes-repo-no-remote "$(block_of '~/.local/share/agent-notes')" '  - no remote'
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

ignored_repo=$ghq_root/example.com/owner/ignored-files
has ignored-files-named "$(block_of example.com/owner/ignored-files)" 'ignored files no build re-creates: 2 (`data/app.sqlite`, `local-notes.md`)'
has ignored-files-by-hand "$(block_of example.com/owner/ignored-files)" 'copy by hand the ignored files to keep: `--backup-paths` does not list them'
has ignored-credential-listed "$credentials" "\`$ignored_repo/data/$pem_name\`"
# shellcheck disable=SC2088
if block_of '~/.gnupg' | grep -qF 'ignored files no build re-creates'; then
  fail credential-location-not-offered 'files in a credential location are offered to copy'
else
  ok credential-location-not-offered
fi
folders=$(sed -n '/^## Large user folders/,/^## LaunchAgents/p' "$work_dir/out")
has user-folders-by-hand "$folders" '`--backup-paths` does not list them'
# shellcheck disable=SC2088
has user-folder-counted "$folders" '`~/Documents`: 3 file(s)'
records=()
while IFS= read -r -d '' record; do records+=("$record"); done <"$work_dir/paths"
is_record() { # <path>
  local record
  for record in ${records[@]+"${records[@]}"}; do [[ $record == "$1" ]] && return 0; done
  return 1
}
for path in "$memory/MEMORY.md" "$notes/note.md" "$unicode_note"; do
  if is_record "$path"; then ok "backup-path ${path#"$root"/}"; else fail "backup-path ${path#"$root"/}" 'not listed'; fi
done
if is_record "$forged"; then ok backup-paths-newline-name-whole; else fail backup-paths-newline-name-whole 'a name holding a newline is not one record'; fi
outside=$(for record in ${records[@]+"${records[@]}"}; do if [[ $record != "$memory"/* && $record != "$notes"/* ]]; then printf '%s ' "$record"; fi; done)
if [[ -z $outside ]]; then ok backup-paths-roots-only; else fail backup-paths-roots-only "$outside"; fi
for name in "$env_name" TOKEN-rotation fifo hardlinked outside "$ed_name" .p8 "$marker"; do
  leaked=$(for record in ${records[@]+"${records[@]}"}; do if [[ $record == *"$name"* ]]; then printf '%s ' "$record"; fi; done)
  if [[ -n $leaked ]]; then fail "backup-paths-leave-out $name" "$leaked"; else ok "backup-paths-leave-out $name"; fi
done
leaked=$(for record in ${records[@]+"${records[@]}"}; do
  for location in "$credential_dir" "$gnupg_dir"; do
    if [[ $record == "$location" || $record == "$location"/* ]]; then printf '%s ' "$record"; fi
  done
done)
if [[ -n $leaked ]]; then fail backup-paths-no-credential-location "$leaked"; else ok backup-paths-no-credential-location; fi
# Each file below a backup root is listed, or the report names it and why not.
left_out=$(sed -n '/^## Notes and agent state/,/^## Shell history/p' "$work_dir/out")
while IFS= read -r -d '' file; do
  if is_record "$file" || grep -qF -- "\`~/${file#"$home"/}\`: left out of \`--backup-paths\`" <<<"$left_out"; then
    ok "listed-or-named ${file#"$home"/}"
  else
    fail "listed-or-named ${file#"$home"/}" 'neither listed nor named in the report'
  fi
done < <(find "$memory" "$notes" -name .git -prune -o ! -type d -print0)
for pair in "fifo:not a regular file" "hardlinked.md:another hard link to it exists" "outside.md:a symlink, which is not followed" \
  "TOKEN-rotation.md:its name suggests a secret" "ssh/$key_name:it is in a credential location"; do
  has "left-out-why ${pair%%:*}" "$left_out" "memory/${pair%%:*}\`: left out of \`--backup-paths\`: ${pair#*:}"
done
not_paths=$(for record in ${records[@]+"${records[@]}"}; do if [[ ! -e $record && ! -L $record ]]; then printf '%s ' "$record"; fi; done)
if [[ -z $not_paths ]]; then ok backup-paths-only-paths; else fail backup-paths-only-paths "$not_paths"; fi
if tar --null -cf "$work_dir/backup.tar" -T "$work_dir/paths" 2>/dev/null && tar -tf "$work_dir/backup.tar" >"$work_dir/archived"; then
  # bsdtar lists a name in decomposed Unicode, so only its ASCII parts are matched.
  has tar-takes-the-list "$(grep -F 'agent-notes/uni code ' "$work_dir/archived")" '.md'
  # Not piped into `grep -q`: under pipefail, tar killed by the early exit would read as no match.
  tar -xOf "$work_dir/backup.tar" >"$work_dir/archived-contents"
  if grep -qF -- "$marker" "$work_dir/archived-contents"; then fail backup-holds-no-credential 'the fixture key contents are in the archive'; else ok backup-holds-no-credential; fi
else
  fail tar-takes-the-list 'tar could not archive the list'
fi
has atuin-export-hint "$(cat "$work_dir/err-paths")" 'atuin history list'
has backup-scope-said "$(cat "$work_dir/err-paths")" 'Desktop, Documents, Downloads, Pictures, and the files repositories ignore are not'
if [[ -s $work_dir/paths-no-realpath ]]; then fail no-realpath-lists-nothing "$(tr '\0' ' ' <"$work_dir/paths-no-realpath")"; else ok no-realpath-lists-nothing; fi
has no-realpath-said "$(cat "$work_dir/err-no-realpath")" 'realpath is not installed'
moved=$(tr '\0' '\n' <"$work_dir/paths-ssh-documents")
has ssh-in-documents-run "$moved" "$memory/MEMORY.md"
leaked=$(while IFS= read -r -d '' record; do if [[ $record == "$home/Documents"/* || $record == "$home/.ssh"/* ]]; then printf '%s ' "$record"; fi; done <"$work_dir/paths-ssh-documents")
if [[ -n $leaked ]]; then fail ssh-in-documents-not-listed "$leaked"; else ok ssh-in-documents-not-listed; fi

if diff "$work_dir/before" "$work_dir/after" >"$work_dir/diff"; then
  ok nothing-changed
else
  fail nothing-changed "$(head -5 "$work_dir/diff" | tr '\n' ' ')"
fi

echo "summary: $checks checks, $failures failed"
((failures == 0))
