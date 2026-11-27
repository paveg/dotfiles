#!/usr/bin/env bash
# List what wiping this machine would lose, without changing anything: work in
# git that is not committed or not pushed, notes and agent state, history,
# credential locations, containers, local databases, software to reinstall,
# files no dotfiles manage, and LaunchAgents. The report is Markdown on stdout
# and the run always exits 0. It writes nothing itself, runs no fetch, asks the
# tools it calls to stay offline (a tool may still update its own cache), and
# for credential locations reports names, counts, and sizes only, never contents.
# Usage: scripts/pre-wipe-inventory.sh >/tmp/inventory.md   (keep the report out
#        of the checkout: it names private paths)
# Env: HOME; GHQ_ROOT (default: `ghq root`, else ~/repos); AGENT_NOTES_DIR
#      (default: ~/.local/share/agent-notes). Runs on macOS's bash 3.2.
# SC2016: backticks inside single quotes are Markdown code spans in the report.
# shellcheck disable=SC2016
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)

export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
export NPM_CONFIG_UPDATE_NOTIFIER=false DO_NOT_TRACK=1 MISE_OFFLINE=1 GIT_TERMINAL_PROMPT=0

have() { command -v "$1" >/dev/null 2>&1; }

real_path() { (cd "$1" 2>/dev/null && pwd -P); }

ghq_roots=''
if [[ -n ${GHQ_ROOT:-} ]]; then
  ghq_roots=$(tr ':' '\n' <<<"$GHQ_ROOT")
elif have ghq; then
  ghq_roots=$(ghq root --all 2>/dev/null)
fi
[[ -n $ghq_roots ]] || ghq_roots=$HOME/repos
home_real=$(real_path "$HOME")
home_real=${home_real:-$HOME}
notes_dir=${AGENT_NOTES_DIR:-$HOME/.local/share/agent-notes}
claude_dir=$HOME/.claude

section_titles=()
section_items=()
section_actions=()
current=-1

section() { # <title> <what to do>
  current=$((current + 1))
  section_titles[current]=$1
  section_items[current]=0
  section_actions[current]=0
  printf '\n## %s\n\nWhat to do: %s\n\n' "$1" "$2"
}

listed() { # <text>   an item the wipe does not lose
  section_items[current]=$((section_items[current] + 1))
  printf -- '- %s\n' "$1"
}

needs_action() { # <text>
  section_items[current]=$((section_items[current] + 1))
  section_actions[current]=$((section_actions[current] + 1))
  printf -- '- **needs action:** %s\n' "$1"
}

note() { # <text>   the state of a probe, not an item
  printf -- '- %s\n' "$1"
}

detail() { # <text>
  printf -- '  - %s\n' "$1"
}

subsection() { # <title>
  printf '\n### %s\n\n' "$1"
}

# SC2088: the tilde is printed for the reader, not expanded.
# shellcheck disable=SC2088
tilde() { # <path>
  case $1 in
    "$HOME" | "$home_real") printf '~' ;;
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    "$home_real"/*) printf '~/%s' "${1#"$home_real"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

count_lines() { grep -c . ; }

format_kib() { # <KiB>
  awk -v k="$1" 'BEGIN {
    if (k >= 1048576) printf "%.1f GiB", k / 1048576
    else if (k >= 1024) printf "%.1f MiB", k / 1024
    else printf "%d KiB", k
  }'
}

size_of() { # <path>   disk usage from metadata; never opens a file
  local out kib suffix=''
  out=$(du -sk "$1" 2>/dev/null) || suffix=' (some entries could not be read)'
  kib=${out%%[[:space:]]*}
  if [[ -z $kib ]]; then
    printf 'size unknown (could not read)'
    return
  fi
  printf '%s%s' "$(format_kib "$kib")" "$suffix"
}

file_count() { # <dir>
  find "$1" -name .git -prune -o ! -type d -print 2>/dev/null | count_lines
}

describe_location() { # <path>   names, counts, and sizes only; never opens a file
  local listing names
  if [[ -d $1 ]]; then
    if listing=$(ls -A "$1" 2>/dev/null); then
      names=$(printf '%s\n' "$listing" | awk 'NF && n < 20 { printf "%s%s", sep, $0; sep = ", "; n++ } NF { total++ } END { if (total > 20) printf ", and %d more", total - 20 }')
    else
      names='could not read'
    fi
    printf '`%s`: directory, %s file(s), %s; entries: %s' "$(tilde "$1")" "$(file_count "$1")" "$(size_of "$1")" "${names:-none}"
  else
    printf '`%s`: file, %s' "$(tilde "$1")" "$(size_of "$1")"
  fi
}

# Read-only git: without optional locks `git status` does not rewrite the index,
# and a repository's fsmonitor hook, which would run a program, stays off.
git_ro() { GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false "$@"; }

# `-c` arguments, one per line, that empty every filter the repository's
# configuration names, so `git status` runs no clean or smudge program.
filter_overrides() { # <work tree>
  local name
  git_ro -C "$1" config --name-only --get-regexp '^filter\.' 2>/dev/null | sed 's/^filter\.//; s/\.[^.]*$//' | LC_ALL=C sort -u |
    while IFS= read -r name; do
      printf -- '-c\nfilter.%s.%s\n' "$name" clean= "$name" smudge= "$name" process= "$name" required=false
    done
}

worktree_changes() { # <work tree>   prints "<tracked changes> <untracked files>"
  local tracked untracked arg overrides=()
  while IFS= read -r arg; do overrides+=("$arg"); done < <(filter_overrides "$1")
  # Each submodule is reported as its own repository, so the parent's status
  # neither counts nor enters a submodule's work tree.
  tracked=$(git_ro ${overrides[@]+"${overrides[@]}"} -C "$1" status --porcelain --untracked-files=no --ignore-submodules=dirty 2>/dev/null) || return 1
  untracked=$(git_ro -C "$1" ls-files --others --exclude-standard 2>/dev/null) || return 1
  printf '%s %s\n' "$(printf '%s' "$tracked" | count_lines)" "$(printf '%s' "$untracked" | count_lines)"
}

repo_findings() { # <main work tree or bare repository> <work|bare>   one line per thing the wipe would lose, then the next step
  local dir=$1 kind=$2 out count ref upstream track worktree tracked untracked remotes sha
  local unsaved=0 dirty=0 stashes=0 total=0 off_branch=0 branches='' at=() heads=()
  finding() { unsaved=1; echo "$1"; }
  if [[ $kind == bare ]]; then at=(--git-dir="$dir"); else at=(-C "$dir"); fi
  if ! git_ro "${at[@]}" rev-parse --git-dir >/dev/null 2>&1; then
    echo 'git cannot read this repository'
    echo 'next: check it by hand'
    return
  fi
  out=$(git_ro "${at[@]}" worktree list --porcelain 2>/dev/null) || finding '`git worktree list` failed, so linked worktrees are not checked'
  while IFS= read -r sha; do heads+=("$sha"); done < <(sed -n 's/^HEAD //p' <<<"$out" | grep -v '^0*$')
  if [[ $kind == work ]]; then
    if read -r tracked untracked < <(worktree_changes "$dir") && [[ -n $untracked ]]; then
      ((tracked > 0)) && { dirty=1; finding "tracked uncommitted changes: $tracked"; }
      ((untracked > 0)) && { dirty=1; finding "untracked files: $untracked"; }
    else
      dirty=1
      finding 'git status failed'
    fi
  fi
  while IFS= read -r worktree; do
    [[ -d $worktree ]] || continue
    if read -r tracked untracked < <(worktree_changes "$worktree") && [[ -n $untracked ]]; then
      ((tracked + untracked > 0)) || continue
      finding "linked worktree \`$(tilde "$worktree")\`: $tracked tracked uncommitted change(s), $untracked untracked file(s)"
    else
      finding "linked worktree \`$(tilde "$worktree")\`: git status failed"
    fi
    dirty=1
  done < <(awk '
    /^worktree / { path = substr($0, 10); n++; bare = 0 }
    /^bare$/ { bare = 1 }
    /^$/ { if (n > 1 && !bare) print path; path = "" }
    END { if (path != "" && n > 1 && !bare) print path }
  ' <<<"$out")
  if git_ro "${at[@]}" rev-parse -q --verify refs/stash >/dev/null 2>&1; then
    stashes=$(git_ro "${at[@]}" log --walk-reflogs --format=%H refs/stash -- 2>/dev/null | count_lines)
    ((stashes > 0)) || stashes=1
    finding "stashes: $stashes"
  fi
  remotes=$(git_ro "${at[@]}" remote 2>/dev/null) || finding '`git remote` failed'
  if total=$(git_ro "${at[@]}" rev-list --count ${heads[@]+"${heads[@]}"} --branches --tags --glob=refs/stash --not --remotes 2>/dev/null); then
    [[ -z $remotes ]] && ((total > 0)) && finding 'no remote'
    ((total > 0)) && finding "commits on no remote ref: $total (from every worktree's HEAD, branch, tag, and the stash)"
  else
    total=1
    finding '`git rev-list` failed, so commits on no remote ref are not counted'
  fi
  while IFS=$'\t' read -r ref upstream track; do
    [[ -n $ref ]] || continue
    if [[ -z $upstream || $track == '[gone]' ]]; then
      count=$(git_ro "${at[@]}" rev-list --count "$ref" --not --remotes 2>/dev/null) || count=failed
      [[ $count == 0 ]] || finding "branch \`${ref#refs/heads/}\`: no upstream, $count commit(s) on no remote branch"
    else
      count=$(git_ro "${at[@]}" rev-list --count "$upstream..$ref" 2>/dev/null) || count=failed
      [[ $count == 0 ]] || finding "branch \`${ref#refs/heads/}\`: $count commit(s) ahead of \`${upstream#refs/remotes/}\`"
    fi
    [[ $count == 0 ]] || branches="$branches ${ref#refs/heads/}"
  done < <(git_ro "${at[@]}" for-each-ref --format='%(refname)%09%(upstream)%09%(upstream:track)' refs/heads 2>/dev/null)
  off_branch=$(git_ro "${at[@]}" rev-list --count ${heads[@]+"${heads[@]}"} --tags --not --branches --remotes 2>/dev/null) || off_branch=0
  ((off_branch > 0)) && finding "on no branch (a detached HEAD or only a tag): $off_branch"
  ((unsaved)) && next_step "$dir" "$remotes" "$dirty" "$stashes" "$off_branch" "$branches"
  return 0
}

next_step() { # <repository> <remotes> <dirty> <stashes> <commits on no branch> <branches to push>
  local quoted="'$1'" name=${1##*/} remote steps=''
  name=${name%.git}.bundle
  [[ $name == *[!A-Za-z0-9._-]* ]] && name="'$name'"
  local bundle="\`git -C $quoted bundle create $name --all\`"
  if [[ -z $2 ]]; then
    if (($3 || $4)); then
      echo "next: commit the uncommitted and untracked work and each stash (a bundle holds commits only), then $bundle"
    else
      echo "next: $bundle"
    fi
    return
  fi
  remote=origin
  grep -qx origin <<<"$2" || remote=$(head -n 1 <<<"$2")
  (($3)) && steps='commit the uncommitted and untracked work'
  (($4)) && steps="${steps:+$steps, }turn each stash into a branch (\`git stash branch <name>\`)"
  (($5)) && steps="${steps:+$steps, }put the commits on no branch on a branch or tag"
  if [[ -z $steps && -n $6 ]]; then
    echo "next: \`git -C $quoted push $remote$6\`"
  elif [[ -n $steps && -n $6 ]]; then
    echo "next: $steps, then push what holds them, and \`git -C $quoted push $remote$6\`"
  elif [[ -n $steps ]]; then
    echo "next: $steps, then push the branch or tag that holds them"
  else
    echo "next: $bundle"
  fi
}

repo_count=0
repo_clean=0
repo_dirs=''

report_repo() { # <label> <main work tree or bare repository> <work|bare>
  local findings line
  repo_count=$((repo_count + 1))
  repo_dirs=$repo_dirs$2$'\n'
  findings=$(repo_findings "$2" "$3")
  if [[ -z $findings ]]; then
    repo_clean=$((repo_clean + 1))
    return
  fi
  needs_action "\`$1\`"
  while IFS= read -r line; do detail "$line"; done <<<"$findings"
}

ghq_roots_real=$(while IFS= read -r root; do real_path "$root"; done <<<"$ghq_roots")
walk_roots=("$home_real")
while IFS= read -r root; do
  [[ -n $root && $root != "$home_real" && $root != "$home_real"/* ]] && walk_roots+=("$root")
done <<<"$ghq_roots_real"
prune_list='`~/Library/Caches`, `~/.Trash`, and every `.cache`, `node_modules`, and `nix/store` directory'

# Every work tree (its `.git` is a directory or, for a linked worktree, a
# submodule, or `--separate-git-dir`, a file) and every bare-repository candidate.
walk() {
  find "${walk_roots[@]}" \( -path "$home_real/Library/Caches" -o -path "$home_real/.Trash" -o -name .cache -o -name node_modules -o -path '*/nix/store' \) -prune \
    -o -name .git -print -prune -o -name HEAD -type f -print 2>/dev/null
}

repo_list=''
seen_repos=''

add_repo() { # <work tree or bare-repository candidate> <work|bare>   one entry per repository, keyed by its common git dir
  local dir=$1 kind=$2 out git_dir common
  if [[ $kind == bare ]]; then
    [[ -d $dir/objects && -d $dir/refs ]] || return 0
    [[ $(git_ro --git-dir="$dir" rev-parse --is-bare-repository 2>/dev/null) == true ]] || return 0
    common=$(real_path "$dir")
  elif out=$(git_ro -C "$dir" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null); then
    git_dir=$(real_path "${out%%$'\n'*}")
    common=$(real_path "${out#*$'\n'}")
    if [[ $git_dir != "$common" ]]; then
      out=$(git_ro -C "$dir" worktree list --porcelain 2>/dev/null | sed '/^$/q')
      dir=$(sed -n 's/^worktree //p' <<<"$out")
      grep -qx bare <<<"$out" && kind=bare
    fi
  else
    common=$dir
  fi
  grep -qxF -- "$common" <<<"$seen_repos" && return 0
  seen_repos=$seen_repos$common$'\n'
  repo_list=$repo_list$dir$'\t'$kind$'\n'
}

repo_label() { # <path>   relative to the ghq root that holds it, else from ~
  local root
  while IFS= read -r root; do
    [[ -n $root && $1 == "$root"/* ]] && { printf '%s' "${1#"$root"/}"; return; }
  done <<<"$ghq_roots_real"
  tilde "$1"
}

chezmoi_paths=''
chezmoi_state='chezmoi not installed, so nothing counts as managed by it'
if have chezmoi; then
  if chezmoi_paths=$(chezmoi managed 2>/dev/null); then
    chezmoi_state='managed means listed by `chezmoi managed`'
  else
    chezmoi_paths=''
    chezmoi_state='`chezmoi managed` failed, so nothing counts as managed by it'
  fi
fi
# What the new dotfiles link, approximated by the names under the checkout's
# home/: close enough for the top-level names the unmanaged-files section checks.
dotfiles_paths=$(cd "$repo_dir/home" 2>/dev/null && find . -mindepth 1 | sed 's|^\./||')

covers() { # <path relative to HOME> <managed paths>   true when it or anything below it is managed
  awk -v p="$1" '$0 == p || index($0, p "/") == 1 { found = 1; exit } END { exit !found }' <<<"$2"
}

is_managed() { # <path relative to HOME> <managed paths>
  grep -qxF -- "$1" <<<"$2"
}

report_unmanaged_below() { # <dir>   a wholly unmanaged directory is one item
  local entry rel
  for entry in "$1"/* "$1"/.[!.]*; do
    [[ -e $entry || -L $entry ]] || continue
    [[ ${entry##*/} == .DS_Store ]] && continue
    rel=${entry#"$HOME"/}
    if [[ -d $entry && ! -L $entry ]]; then
      if covers "$rel" "$chezmoi_paths"; then
        report_unmanaged_below "$entry"
      else
        needs_action "\`$(tilde "$entry")\`: not managed, $(file_count "$entry") file(s), $(size_of "$entry")"
      fi
    elif ! is_managed "$rel" "$chezmoi_paths"; then
      needs_action "\`$(tilde "$entry")\`: not managed, $(size_of "$entry")"
    fi
  done
}

nix_names=''
nix_state='nix not installed: no item is marked as covered by `nix/packages.nix`'
if have nix; then
  # The package list evaluated against the nixpkgs that flake.lock pins, taken
  # from the local store only (--offline), so the probe never downloads.
  if nix_names=$(DOTFILES_REPO=$repo_dir nix --extra-experimental-features 'nix-command flakes' eval --offline --raw --impure --expr '
      let
        repo = builtins.getEnv "DOTFILES_REPO";
        lock = builtins.fromJSON (builtins.readFile (repo + "/flake.lock"));
        pkgs = import (builtins.fetchTree lock.nodes.nixpkgs.locked) { };
        names = p: [ (pkgs.lib.getName p) ] ++ pkgs.lib.optional (p.meta ? mainProgram) p.meta.mainProgram;
      in
      builtins.concatStringsSep "\n" (pkgs.lib.concatMap names (import (repo + "/nix/packages.nix") { inherit pkgs; }).home.packages)
    ' 2>/dev/null) && [[ -n $nix_names ]]; then
    nix_state='items whose name matches a package name or command in `nix/packages.nix` are marked; the match is by exact name, so an alias (for example `helm` for `kubernetes-helm`) is matched only through its command name'
  else
    nix_names=''
    nix_state='`nix eval` of `nix/packages.nix` failed (the pinned nixpkgs may not be in the local store): no item is marked as covered'
  fi
fi

nix_covers() { [[ -n $nix_names ]] && grep -qxF -- "$1" <<<"$nix_names"; }

printf '# Pre-wipe inventory\n\n'
printf 'What wiping this machine would lose. Generated %s on %s, read-only: the script writes nothing and runs no fetch. Each item marked **needs action** is something to save, push, or confirm before the wipe; credential locations show names, counts, and sizes only.\n\n' "$(date '+%Y-%m-%d %H:%M')" "$(uname -s)"
printf -- '- HOME: `%s`\n- ghq roots: %s\n- agent notes: `%s`\n' "$HOME" "$(while IFS= read -r root; do printf '`%s` ' "$(tilde "$root")"; done <<<"$ghq_roots")" "$(tilde "$notes_dir")"
have ghq || note 'ghq: not installed'

section 'Git repositories' 'commit and push, or bundle, what each listed repository holds; each one ends with a next step. Commit counts compare with the remote refs from the last fetch, so run `git fetch` in a repository first if its remote may have moved. Untracked files honour .gitignore; ignored files are not counted.'
note "Searched \`~\` and every ghq root for work trees (a \`.git\` directory or file) and bare repositories, skipping $prune_list; symlinks are not followed. Each submodule and each linked worktree's repository is checked as a repository of its own."
while IFS= read -r path; do
  case $path in
    */.git) add_repo "${path%/.git}" work ;;
    */HEAD) add_repo "${path%/HEAD}" bare ;;
  esac
done < <(walk)
notes_real=$(real_path "$notes_dir")
while IFS=$'\t' read -r dir kind; do
  [[ -n $dir && $dir != "$notes_real" ]] && report_repo "$(repo_label "$dir")" "$dir" "$kind"
done < <(printf '%s' "$repo_list" | LC_ALL=C sort)
section_items[current]=$((section_items[current] + repo_clean))
note "Clean repositories (counted, not listed): $repo_clean"

section 'Notes and agent state outside git' 'push or back up each listed location: agent notes and Claude Code memory and transcripts exist only on this disk unless they are pushed or copied.'
if [[ -d $notes_dir ]]; then
  summary="agent notes \`$(tilde "$notes_dir")\`: $(file_count "$notes_dir") file(s), $(size_of "$notes_dir")"
  if [[ -e $notes_dir/.git ]]; then
    findings=$(repo_findings "$notes_dir")
    if [[ -z $findings ]]; then
      listed "$summary; a git repository with everything committed and pushed"
    else
      needs_action "$summary; a git repository with unsaved work"
      while IFS= read -r line; do detail "$line"; done <<<"$findings"
    fi
  else
    needs_action "$summary; not a git repository"
  fi
else
  note "agent notes \`$(tilde "$notes_dir")\`: not found"
fi
found=0
for memory in "$claude_dir"/projects/*/memory; do
  [[ -d $memory ]] || continue
  count=$(file_count "$memory")
  ((count > 0)) || continue
  found=1
  project=${memory%/memory}
  needs_action "Claude Code memory for \`${project##*/}\`: $count file(s)"
done
((found)) || note 'Claude Code memory: none found'
count=0
[[ -d $claude_dir/projects ]] && count=$(find "$claude_dir/projects" -type f -name '*.jsonl' 2>/dev/null | count_lines)
if ((count > 0)); then
  kib=$(find "$claude_dir/projects" -type f -name '*.jsonl' -exec du -k {} + 2>/dev/null | awk '{ total += $1 } END { print total + 0 }')
  needs_action "Claude Code session transcripts: $count file(s), $(format_kib "$kib")"
else
  note 'Claude Code session transcripts: none found'
fi
if [[ -d $claude_dir ]]; then
  note "Entries under \`~/.claude\` chezmoi does not manage ($chezmoi_state):"
  report_unmanaged_below "$claude_dir"
else
  note '`~/.claude`: not found'
fi

section 'Shell history and tool data' 'copy each listed location somewhere safe to keep it; the new dotfiles keep shell history in atuin only. The atuin data directory is described, never read.'
found=0
seen=''
for dir in "${ATUIN_HOME:-}" "$HOME/.local/share/atuin" "$HOME/.atuin"; do
  [[ -n $dir && -d $dir ]] || continue
  case $seen in *"|$dir|"*) continue ;; esac
  seen="$seen|$dir|"
  found=1
  needs_action "atuin data $(describe_location "$dir"); it holds atuin's key, so confirm this is in 1Password or can be re-created"
done
for file in .zsh_history .bash_history .config/zsh/.zsh_history .local/state/zsh/history \
  .local/share/fish/fish_history .python_history .node_repl_history .psql_history .mysql_history .sqlite_history; do
  [[ -f $HOME/$file ]] || continue
  found=1
  needs_action "history file $(describe_location "$HOME/$file")"
done
for dir in "${_ZO_DATA_DIR:-}" "$HOME/.local/share/zoxide" "$HOME/Library/Application Support/zoxide"; do
  [[ -n $dir && -d $dir ]] || continue
  found=1
  needs_action "zoxide data $(describe_location "$dir")"
done
((found)) || note 'none found'

section 'Credentials' 'confirm each listed location is in 1Password or can be re-created. Only names, counts, and sizes are shown; no file was opened.'
for path in .ssh .aws .kube .config/gcloud .config/op .gnupg .netrc .codex .claude/.credentials.json; do
  if [[ -e $HOME/$path ]]; then
    needs_action "$(describe_location "$HOME/$path")"
  else
    note "\`~/$path\`: not found"
  fi
done
note "\`.env\` files (also \`.env.*\`, \`.envrc\`, \`.dev.vars\`) in every repository above to 6 levels, and directly under \`~\`:"
found=0
while IFS= read -r file; do
  [[ -n $file ]] || continue
  git_ro -C "${file%/*}" ls-files --error-unmatch -- "${file##*/}" >/dev/null 2>&1 && continue
  found=1
  needs_action "$(describe_location "$file")"
done < <(
  {
    while IFS= read -r dir; do
      [[ -n $dir ]] && find "$dir" -maxdepth 6 \( -name .git -o -name node_modules \) -prune -o \
        \( -name .env -o -name '.env.*' -o -name .envrc -o -name .dev.vars \) ! -type d -print 2>/dev/null
    done <<<"$repo_dirs"
    find "$HOME" -maxdepth 1 \( -name .env -o -name '.env.*' -o -name .envrc \) ! -type d -print 2>/dev/null
  } | sed -E '/\.env\.(example|sample|template)$/d' | LC_ALL=C sort -u
)
((found)) || note 'none found'

section 'Containers and VMs' 'export or recreate each listed image, volume, and VM; their data lives inside the VM disk and is lost with it.'
if ! have docker; then
  note 'docker: not installed'
elif docker info >/dev/null 2>&1; then
  found=0
  while IFS= read -r line; do
    [[ -n $line ]] && { found=1; needs_action "docker image \`$line\`"; }
  done < <(docker images --format '{{.Repository}}:{{.Tag}} ({{.Size}})' 2>/dev/null)
  while IFS= read -r line; do
    [[ -n $line ]] && { found=1; needs_action "docker volume \`$line\`"; }
  done < <(docker volume ls --format '{{.Name}}' 2>/dev/null)
  ((found)) || note 'docker: no images or volumes'
else
  note 'docker: the daemon is not running, so images and volumes are not listed (check with `docker info`)'
fi
# colima and lima keep each VM's disk on this machine whether it runs or not,
# so their instances are listed either way.
if ! have colima; then
  note 'colima: not installed'
else
  colima status >/dev/null 2>&1 || note 'colima: not running (check with `colima status`); its VMs are listed below anyway'
  found=0
  while IFS= read -r line; do
    [[ -n $line ]] && { found=1; needs_action "colima VM: \`$line\`"; }
  done < <(colima list 2>/dev/null | tail -n +2 | awk '{ print $1 " (" $2 ")" }')
  ((found)) || note 'colima: no VMs'
fi
if ! have limactl; then
  note 'lima: not installed'
else
  found=0
  while IFS= read -r line; do
    [[ -n $line ]] && { found=1; needs_action "lima instance: \`$line\`"; }
  done < <(limactl list --format '{{.Name}} ({{.Status}})' 2>/dev/null)
  ((found)) || note 'lima: no instances (check with `limactl list`)'
fi

section 'Local databases' 'dump each listed data directory (for example `pg_dumpall`, `mysqldump`, or a Redis snapshot) before the wipe.'
brew_prefix=''
have brew && brew_prefix=$(brew --prefix 2>/dev/null)
if [[ -z $brew_prefix ]]; then
  note 'Homebrew: not installed'
else
  found=0
  for dir in "$brew_prefix"/var/postgres* "$brew_prefix"/var/mysql* "$brew_prefix"/var/redis* "$brew_prefix"/var/db/redis*; do
    [[ -d $dir ]] || continue
    found=1
    needs_action "\`$dir\`: $(size_of "$dir")"
  done
  ((found)) || note "no postgres, mysql, or redis data under \`$brew_prefix/var\`"
  subsection '`brew services list`'
  while IFS= read -r line; do
    [[ -n $line ]] && listed "\`$line\`"
  done < <(brew services list 2>/dev/null | tail -n +2 | awk '{ print $1 " " $2 }')
fi

section 'Installed software' "reinstall each listed item on the new machine, or add it to the dotfiles. Items marked as in \`nix/packages.nix\` come back with the first switch. Marking: $nix_state. Casks and App Store apps are never marked: that list holds CLI packages, and a cask can share a command's name."

# <mark> is "nix" to mark items that nix/packages.nix covers, "apps" not to.
software() { # <title> <mark> <sed -E -n program> <command>...   one item per line; its first word names the package
  local title=$1 mark=$2 program=$3 out line name
  shift 3
  subsection "$title"
  if ! have "$1"; then
    note "$1: not installed"
    return
  fi
  if ! out=$("$@" 2>/dev/null | sed -E -n "$program"); then
    needs_action "\`$*\` failed; list this by hand"
    return
  fi
  found=0
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    found=1
    name=${line%% *}
    name=${name##*/}
    name=${name%@*}
    if [[ $mark == nix ]] && nix_covers "$name"; then
      listed "\`$line\` (in \`nix/packages.nix\`)"
    else
      needs_action "\`$line\`"
    fi
  done <<<"$out"
  ((found)) || note 'none'
}

mas_names='s/^[0-9]+[[:space:]]+//; s/[[:space:]]+\([^)]*\)[[:space:]]*$//; p'
software '`brew leaves`' nix p brew leaves
software '`brew list --cask`' apps p brew list --cask -1
software '`mas list`' apps "$mas_names" mas list
software '`devbox global list`' nix 's/^\* //p' devbox global list
software 'global npm packages' nix 's|.*/node_modules/||p' npm ls -g --depth=0 --parseable
software 'global pnpm packages' nix 's|.*/node_modules/||p' pnpm ls -g --depth=0 --parseable
software '`uv tool list`' nix '/^-/!p' uv tool list
software '`cargo install --list`' nix '/^[[:space:]]/!p' cargo install --list
software '`mise ls`' nix 's/^([^ ]+) +([^ ]+).*/\1 \2/p' mise ls

subsection 'Apps in `/Applications` from neither Homebrew nor the App Store'
if [[ ! -d /Applications ]]; then
  note '`/Applications`: not found'
else
  cask_apps=''
  cask_tokens=''
  if have brew; then
    cask_tokens=$(brew list --cask -1 2>/dev/null)
    if ! have jq; then
      note 'jq: not installed, so a cask app is recognised only when its name matches the cask token; some cask apps may be listed below'
    else
      cask_apps=$(brew info --cask --installed --json=v2 2>/dev/null |
        jq -r '.casks[].artifacts[] | objects | .app // empty | .[] | if type == "string" then . elif type == "object" then (.target // empty) else empty end' 2>/dev/null |
        sed 's|.*/||')
    fi
  fi
  mas_apps=''
  have mas && mas_apps=$(mas list 2>/dev/null | sed -E -n "$mas_names")
  covered=0
  for app in /Applications/*.app; do
    [[ -d $app ]] || continue
    name=${app##*/}
    token=$(printf '%s' "${name%.app}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    bundle_id=''
    have defaults && bundle_id=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
    if [[ -d $app/Contents/_MASReceipt ]] || grep -qxF -- "${name%.app}" <<<"$mas_apps" ||
      grep -qxF -- "$name" <<<"$cask_apps" || grep -qxF -- "$token" <<<"$cask_tokens" ||
      [[ $bundle_id == com.apple.* ]]; then
      covered=$((covered + 1))
    else
      needs_action "\`$name\`"
    fi
  done
  section_items[current]=$((section_items[current] + covered))
  note "Apps from Homebrew casks, the App Store, or Apple (counted, not listed): $covered"
fi

section 'Files no dotfiles manage' "for each listed name, back it up, add it to the dotfiles, or let it go. Names only. A name counts as managed when chezmoi manages it or anything below it ($chezmoi_state), or when the new dotfiles' \`home/\` holds it. Names that other sections report, and the macOS bookkeeping files \`.Trash\`, \`.DS_Store\`, and \`.CFUserTextEncoding\`, are left out."
found=0
for entry in "$HOME"/* "$HOME"/.[!.]* "$HOME"/.config/* "$HOME"/.config/.[!.]*; do
  [[ -e $entry || -L $entry ]] || continue
  rel=${entry#"$HOME"/}
  case $rel in
    Desktop | Documents | Downloads | Pictures | .Trash | .DS_Store | */.DS_Store | .CFUserTextEncoding | .config | .claude | .atuin | \
      .ssh | .aws | .kube | .gnupg | .netrc | .codex | .config/gcloud | .config/op | \
      .zsh_history | .bash_history | .python_history | .node_repl_history | .psql_history | .mysql_history | .sqlite_history | \
      .env | .env.* | .envrc)
      continue
      ;;
  esac
  grep -qxF -- "$entry" <<<"$ghq_roots" && continue
  [[ $rel != */* && -d $entry/.git ]] && continue
  covers "$rel" "$chezmoi_paths" && continue
  covers "$rel" "$dotfiles_paths" && continue
  found=1
  needs_action "\`~/$rel\`"
done
((found)) || note 'none found'

section 'Large user folders' 'move what you want to keep to iCloud Drive, an external disk, or another machine.'
for name in Documents Desktop Downloads Pictures; do
  if [[ -d $HOME/$name ]]; then
    needs_action "\`~/$name\`: $(size_of "$HOME/$name")"
  else
    note "\`~/$name\`: not found"
  fi
done
icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
where='System Settings > your name > iCloud > iCloud Drive > Desktop & Documents Folders'
if [[ -d $icloud/Desktop || -d $icloud/Documents ]]; then
  note "iCloud Drive holds a Desktop or Documents folder, so Desktop & Documents sync looks on; confirm in $where."
elif [[ -d $icloud ]]; then
  note "iCloud Drive holds no Desktop or Documents folder, so Desktop & Documents sync looks off; confirm in $where."
else
  note "iCloud Drive not found or not readable: whether Desktop & Documents sync is on cannot be told; check $where."
fi

section 'LaunchAgents' 'decide for each listed agent whether the new setup recreates it (nix-darwin, an app reinstall) or whether to keep a copy.'
found=0
for plist in "$HOME"/Library/LaunchAgents/*; do
  [[ -e $plist ]] || continue
  found=1
  needs_action "\`${plist##*/}\`"
done
((found)) || note '`~/Library/LaunchAgents`: none found'

printf '\n## Summary\n\n| Section | Items | Need action |\n|---|---|---|\n'
total_items=0
total_actions=0
for ((i = 0; i <= current; i++)); do
  printf '| %s | %d | %d |\n' "${section_titles[i]}" "${section_items[i]}" "${section_actions[i]}"
  total_items=$((total_items + section_items[i]))
  total_actions=$((total_actions + section_actions[i]))
done
printf '| Total | %d | %d |\n' "$total_items" "$total_actions"
exit 0
