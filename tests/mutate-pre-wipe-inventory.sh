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
# The script reads nix/ and home/ beside its own directory, so each copy sits
# in a scripts/ directory beside links to them.
mkdir "$work/scripts"
ln -s "$repo_dir/nix" "$work/nix"
ln -s "$repo_dir/home" "$work/home"
failures=0

expect_caught() { # <description> <old> <new>
  local copy=$work/scripts/pre-wipe-inventory.sh
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

cp "$script" "$work/scripts/pre-wipe-inventory.sh"
"$repo_dir/tests/pre-wipe-inventory.sh" "$work/scripts/pre-wipe-inventory.sh" >/dev/null || { echo "FAIL: an unmutated copy fails its tests"; exit 1; }
expect_caught 'tracked changes are not reported' '((tracked > 0)) && { dirty=1; finding "tracked uncommitted changes: $tracked"; }' ':'
expect_caught 'stashes are not reported' '    finding "stashes: $stashes"' '    :'
expect_caught 'a branch ahead of its upstream is not reported' '[[ $count == 0 ]] || finding "branch \`${ref#refs/heads/}\`: $count commit(s) ahead' 'true || finding "branch \`${ref#refs/heads/}\`: $count commit(s) ahead'
expect_caught 'a branch with no upstream is not reported' '[[ $count == 0 ]] || finding "branch \`${ref#refs/heads/}\`: no upstream' 'true || finding "branch \`${ref#refs/heads/}\`: no upstream'
expect_caught 'a repository with no remote is not reported' "&& finding 'no remote'" '&& :'
expect_caught 'a repository git cannot read is counted as clean' "echo 'git cannot read this repository'" ':'
expect_caught 'a .git file is not taken for a work tree' '-o -name .git -print -prune' '-o -name .git -type d -print -prune'
expect_caught 'bare repositories are not found' '*/HEAD) add_repo "${path%/HEAD}" bare ;;' '*/HEAD) : ;;'
expect_caught 'the walk stops at a fixed depth' 'find "${walk_roots[@]}" \(' 'find "${walk_roots[@]}" -maxdepth 5 \('
expect_caught 'ghq roots outside HOME are not walked' '&& walk_roots+=("$root")' '&& :'
expect_caught 'a ghq root list is read as one path' "ghq_roots=\$(tr ':' '\n' <<<\"\$GHQ_ROOT\")" 'ghq_roots=$GHQ_ROOT'
expect_caught 'a repository found twice is reported twice' 'grep -qxF -- "$common" <<<"$seen_repos" && return 0' ':'
expect_caught 'worktree HEADs are not counted' 'heads+=("$sha")' ':'
expect_caught 'commits only on a ref outside heads and tags are not counted' '--all --reflog --not --remotes' '--branches --tags --glob=refs/stash --reflog --not --remotes'
expect_caught 'commits only a reflog holds are not counted' '--all --reflog --not --remotes' '--all --not --remotes'
expect_caught 'commits on no branch are not named' '((off_branch > 0)) && finding' 'false && finding'
expect_caught 'a linked worktree with changes is skipped' '((tracked + untracked > 0)) || continue' 'continue'
expect_caught 'a repository clean filter runs' 'done < <(filter_overrides "$1")' 'done < <(:)'
expect_caught 'commits only a reflog holds get no ref before the bundle' 'done < <(reflog_only_tips "$1")' 'done < <(:)'
expect_caught 'the push next step drops commits only a reflog holds' '[[ -n $rescue && $text != "$bundle" ]] && text=' 'false && text='
expect_caught 'the bundle next step is wrong' 'name=${name%.git}.bundle' 'name=${name%.git}.tar'
expect_caught 'the push next step is wrong' '      text="\`git -C $quoted push $remote$6\`"' '      text=push'
expect_caught 'uncommitted work is not committed first' "((\$3)) && steps='commit the uncommitted and untracked work'" ':'
expect_caught 'env files the walk finds are dropped' "*) env_files=\$env_files\$path\$'\\n' ;;" '*) : ;;'
expect_caught 'ignored files are not reported' '      finding "ignored files no build re-creates: $count ($names)"' '      :'
expect_caught 'ignored files get no next step' '(($8)) && text=' 'false && text='
expect_caught 'a credential-named ignored file is not listed under Credentials' 'repo_ignored_files | grep -ziE "$credential_name" |' ': | grep -ziE "$credential_name" |'
expect_caught 'credential-named ignored files are offered to copy' 'grep -zviE "$credential_name" | while' 'cat | while'
expect_caught 'ignored files are read newline-separated' 'git_ro -C "$1" ls-files -z --others' 'git_ro -C "$1" ls-files --others'
expect_caught 'an ignored file in a credential location is offered to copy' '[[ $path == "$location" || $path == "$location"/* ]] && continue 2' ':'
expect_caught 'build outputs are offered to copy' '|dist|build|' '|dist|'
expect_caught 'an ignored directory is offered whole' '(cd "$1" && find "${entry%/}" -name .git -prune -o ! -type d -print0 2>/dev/null)' 'printf "%s\0" "$entry"'
expect_caught 'Claude Code memory is no backup root' '"$claude_dir"/projects/*/memory # Claude Code memory' '# Claude Code memory'
expect_caught 'the agent notes are no backup root' '"$notes_dir"                    # agent notes' '# agent notes'
expect_caught 'Documents is a backup root' '"$notes_dir"                    # agent notes' '"$notes_dir" "$HOME/Documents" # agent notes'
expect_caught 'a memory root that resolves elsewhere is listed' '[[ $2 == "$home_real/.claude/projects/$project/memory" && -n $project && $project != */* ]] ||' 'true ||'
expect_caught 'AGENT_NOTES_DIR outside HOME is listed' '[[ $2 == "$home_real"/?* ]] ||' 'true ||'
expect_caught 'AGENT_NOTES_DIR set to HOME is listed' '[[ $2 == "$home_real"/?* ]]' '[[ $2 == "$home_real"* ]]'
expect_caught 'the default agent notes are listed wherever they resolve' '[[ $2 == "$home_real/.local/share/agent-notes" ]] ||' 'true ||'
expect_caught 'a refused backup root goes unnamed' "{ printf '%s\0%s\0' \"\$why\" \"\$root\"; continue; }" '{ continue; }'
expect_caught 'a refused backup root is scanned anyway' '"$root"; continue; }' '"$root"; }'
expect_caught 'a symlink below a backup root is followed' 'find "$real" "${prune[@]}" -type f -links 1' 'find -L "$real" "${prune[@]}" -type f -links 1'
expect_caught 'a path that is no regular file is listed' 'find "$real" "${prune[@]}" -type f -links 1' 'find "$real" "${prune[@]}" ! -type d -links 1'
expect_caught 'a file with a second hard link is listed' '-type f -links 1 -print0' '-type f -print0'
expect_caught 'a symlinked credential location is not resolved' '[[ -e $location ]] && location=$(realpath' 'false && location=$(realpath'
expect_caught 'a file in a credential location is listed' "&& why='it is in a credential location'" '&& :'
expect_caught 'a credential-named file below a backup root is listed' '[[ $path =~ $credential_name ]] && why=' 'false && why='
expect_caught 'a password-named file is listed' '(secret|credential|token|password)' '(secret|credential|token)'
expect_caught 'a .git directory below a backup root is listed' 'prune=(\( -name .git -o -name node_modules' 'prune=(\( -name node_modules'
expect_caught 'a credential name is matched case-sensitively' '      shopt -s nocasematch' '      :'
expect_caught 'without realpath the files are listed anyway' 'have realpath || why=' 'true || why='
expect_caught 'backup paths are separated by newlines' "      printf '%s\0' \"\$path\"
    else" "      printf '%s\n' \"\$path\"
    else"
expect_caught 'backup candidates are found newline-separated' '-type f -links 1 -print0 2>/dev/null' '-type f -links 1 -print 2>/dev/null'
expect_caught 'a file left out goes unnamed in the report' '  needs_action "\`$(tilde "$path" | tr' '  : "\`$(tilde "$path" | tr'
expect_caught 'the backup scope goes unsaid' "echo 'Only the files below Claude Code memory" ": 'Only the files below Claude Code memory"
expect_caught 'the backup list runs git' '  backup_paths
  exit 0' '  git -C "$HOME" status >/dev/null 2>&1; backup_paths
  exit 0'
expect_caught 'the user folders are not counted' '$(file_count "$HOME/$name") file(s), ' ''
expect_caught 'the user folders are not said to be left to the owner' ' `--backup-paths` does not list them: what to copy from them is yours to decide by hand.' ''
expect_caught 'the report follows the backup list' '  backup_paths
  exit 0' '  backup_paths'
expect_caught 'the atuin export hint is missing' 'echo "atuin history is left out:' ': "atuin history is left out:'
expect_caught 'agent notes in git are checked without a kind' 'findings=$(repo_findings "$notes_dir" work)' 'findings=$(repo_findings "$notes_dir")'
expect_caught 'a deleted upstream is not pruned first' 'run `git fetch --prune` in a repository' 'run `git fetch` in a repository'
expect_caught 'clean repositories are listed' 'if [[ -z $findings ]]; then
    repo_clean' 'if [[ -z $findings && 1 == 2 ]]; then
    repo_clean'
expect_caught 'clean repositories are left out of the summary' 'section_items[current]=$((section_items[current] + repo_clean))' ':'
expect_caught 'a repository under ~/.config is left out of every section' '[[ $rel != */* && -d $entry/.git ]]' '[[ -d $entry/.git ]]'
expect_caught 'a folder no other section reports is skipped' 'Desktop | Documents | Downloads | Pictures |' 'Desktop | Documents | Downloads | Music | Pictures |'
expect_caught 'the atuin key is not flagged for 1Password' "so confirm this is in 1Password or can be re-created\"" '"'
expect_caught 'chezmoi is run' 'chezmoi_paths=$(cd "$chezmoi_source/$chezmoi_root"' 'chezmoi managed >/dev/null 2>&1; chezmoi_paths=$(cd "$chezmoi_source/$chezmoi_root"'
expect_caught 'chezmoi source names keep dot_' 's#(^|/)dot_#\1.#g; ' ''
expect_caught 'chezmoi source names keep their attributes' '|private|readonly|' '|readonly|'
expect_caught 'chezmoi source names keep .tmpl' 's#\.(tmpl|literal|age|asc)' 's#\.(literal|age|asc)'
expect_caught 'a .chezmoiroot is not followed' '[[ -f $chezmoi_source/.chezmoiroot ]] && read' 'false && read'
expect_caught 'a missing ghq is not reported' "have ghq || note 'ghq: not installed'" ':'
expect_caught 'a credential file is opened and printed' 'listing=$(ls -A "$1" 2>/dev/null)' 'listing=$(cat "$1"/* 2>/dev/null)'
expect_caught 'git status may rewrite the index' 'git_ro() { GIT_OPTIONAL_LOCKS=0 git' 'git_ro() { git'
expect_caught 'the script writes a file' 'export DO_NOT_TRACK=1' ': >"$HOME/.inventory-ran"; export DO_NOT_TRACK=1'
expect_caught 'a missing tool is called anyway' 'have() { command -v "$1" >/dev/null 2>&1; }' 'have() { true; }'
expect_caught 'a probe calls a tool without checking for it' 'if ! have docker; then' 'if false; then'
expect_caught 'a package manager is run instead of read' 'apps "$brew_absent" p entries "$brew_prefix"/Caskroom/*' 'apps "$brew_absent" p brew list --cask'
expect_caught 'formulae installed as dependencies are listed' "grep -l '\"installed_on_request\": *true'" "grep -l '\"installed_on_request\"'"
expect_caught 'a mise version alias is listed' '[[ -d $install && ! -L $install ]] || continue' '[[ -d $install ]] || continue'
expect_caught 'npm is run instead of read' 'npm_packages() { node_packages "${npm_global_dirs[@]}"' 'npm_packages() { node_packages "$(npm root -g)"'
expect_caught 'a vite-plus Node runtime is not read' '"${VITE_PLUS_HOME:-$HOME/.vite-plus}"/js_runtime/node/* ' ''
expect_caught 'the npm bundled with Node is listed' "'/^(npm|corepack)\$/!p' npm_packages" 'p npm_packages'
expect_caught 'scoped npm packages are missed' 'for entry in "$dir"/* "$dir"/@*/*; do' 'for entry in "$dir"/*; do'
expect_caught 'colima VMs are not read' '"${COLIMA_HOME:-$HOME/.colima}"/_lima/*/lima.yaml; do' '; do'
expect_caught 'nothing is marked as in nix/packages.nix' 'nix_covers() { [[ -n $nix_names ]] && grep' 'nix_covers() { false && grep'
expect_caught 'the run exits non-zero' '
exit 0
' '
exit 1
'
expect_caught 'the report has no summary' "printf '\n## Summary" "printf '\n## Totals"
((failures == 0)) && echo "every mutant is caught"
