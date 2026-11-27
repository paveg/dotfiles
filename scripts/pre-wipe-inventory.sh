#!/usr/bin/env bash
# List what wiping this machine would lose, without changing anything: work in
# git that is not committed or not pushed, notes and agent state, history,
# credential locations, containers, local databases, software to reinstall,
# files no dotfiles manage, and LaunchAgents. The report is Markdown on stdout
# and the run always exits 0. It writes nothing itself and runs no fetch. It
# reads package managers' and VMs' files instead of running them; the tools it
# does run are git (read-only, with every configured filter emptied), chezmoi,
# ghq, docker, mas, defaults, `npm root -g`, and `uv tool dir`. Run on an empty
# HOME, the one path it adds is ~/.npm, the empty cache directory npm creates
# when it starts. For credential locations it reports names, counts, and sizes
# only, never contents.
# Usage: scripts/pre-wipe-inventory.sh >/tmp/inventory.md   (keep the report out
#        of the checkout: it names private paths)
#        scripts/pre-wipe-inventory.sh --backup-paths | tar -czf backup.tgz -T -
#        (what cannot be re-created and is not a credential, one path per line)
# Env: HOME; GHQ_ROOT (a colon-separated list; default: `ghq root --all`, else
#      ~/repos); AGENT_NOTES_DIR (default: ~/.local/share/agent-notes). Runs on
#      macOS's bash 3.2.
# SC2016: backticks inside single quotes are Markdown code spans in the report.
# SC2329: the package readers are called by name through software().
# shellcheck disable=SC2016,SC2329
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)

export NPM_CONFIG_UPDATE_NOTIFIER=false DO_NOT_TRACK=1 GIT_TERMINAL_PROMPT=0

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
icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
desktop_documents_synced=0
[[ -d $icloud/Desktop || -d $icloud/Documents ]] && desktop_documents_synced=1

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

# A file name that may hold a secret, matched against a whole path: such a file
# is listed under Credentials and never offered for backup.
credential_name='/(\.env(\..*)?|\.envrc|\.dev\.vars|\.netrc|\.npmrc|\.pypirc|id_(rsa|dsa|ecdsa|ed25519)[^/]*|[^/]*(secret|credential|token|password)[^/]*|[^/]*[._]key|[^/]*\.(pem|p12|pfx|keychain-db))$'
# Ignored paths a build or an install re-creates, matched against a path inside
# a work tree. A fixed list: an ignored output named otherwise is offered for
# backup, which costs space, not data.
regenerable_ignored='(^|/)(node_modules|\.venv|venv|__pycache__|target|dist|build|\.next|\.nuxt|\.turbo|\.cache|\.parcel-cache|coverage|\.direnv|\.devbox|\.terraform|\.gradle|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.tox|\.DS_Store|[^/]*\.pyc)(/|$)'

ignored_files() { # <work tree>   ignored files as absolute paths, without what a build re-creates
  local entry
  git_ro -c core.quotePath=false -C "$1" ls-files --others --ignored --exclude-standard --directory 2>/dev/null |
    grep -vE "$regenerable_ignored" |
    while IFS= read -r entry; do
      if [[ $entry == */ ]]; then
        (cd "$1" && find "${entry%/}" -name .git -prune -o ! -type d -print 2>/dev/null)
      else
        printf '%s\n' "$entry"
      fi
    done | grep -vE "$regenerable_ignored" |
    while IFS= read -r entry; do printf '%s/%s\n' "$1" "$entry"; done
}

linked_worktrees() { # <`git worktree list --porcelain` output>   every work tree but the first entry's
  awk '
    /^worktree / { path = substr($0, 10); n++; bare = 0 }
    /^bare$/ { bare = 1 }
    /^$/ { if (n > 1 && !bare) print path; path = "" }
    END { if (path != "" && n > 1 && !bare) print path }
  ' <<<"$1"
}

worktrees_of() { # <main work tree or bare repository> <work|bare>   every work tree, the main one first
  local at=(-C "$1")
  [[ $2 == bare ]] && at=(--git-dir="$1")
  [[ $2 == work ]] && printf '%s\n' "$1"
  linked_worktrees "$(git_ro "${at[@]}" worktree list --porcelain 2>/dev/null)"
}

repo_findings() { # <main work tree or bare repository> <work|bare>   one line per thing the wipe would lose, then the next step
  local dir=$1 kind=$2 out count ref upstream track worktree tracked untracked remotes sha files file names
  local unsaved=0 dirty=0 stashes=0 total=0 off_branch=0 branches='' git_unsaved ignored=0 at=() heads=()
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
  done < <(linked_worktrees "$out")
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
  git_unsaved=$unsaved
  while IFS= read -r worktree; do
    [[ -d $worktree ]] || continue
    files=$(ignored_files "$worktree" | grep -viE "$credential_name")
    count=$(printf '%s' "$files" | count_lines)
    ((count > 0)) || continue
    ignored=$((ignored + count))
    names=$(while IFS= read -r file; do printf '`%s`\n' "${file#"$worktree"/}"; done <<<"$files" | LC_ALL=C sort |
      awk 'NR <= 5 { printf "%s%s", sep, $0; sep = ", " } END { if (NR > 5) printf ", and %d more", NR - 5 }')
    if [[ $worktree == "$dir" ]]; then
      finding "ignored files to back up: $count ($names)"
    else
      finding "linked worktree \`$(tilde "$worktree")\`: ignored files to back up: $count ($names)"
    fi
  done < <(worktrees_of "$dir" "$kind")
  ((unsaved)) && next_step "$dir" "$remotes" "$dirty" "$stashes" "$off_branch" "$branches" "$git_unsaved" "$ignored"
  return 0
}

next_step() { # <repository> <remotes> <dirty> <stashes> <commits on no branch> <branches to push> <git work unsaved> <ignored files>
  local quoted="'$1'" name=${1##*/} remote steps='' text=''
  name=${name%.git}.bundle
  [[ $name == *[!A-Za-z0-9._-]* ]] && name="'$name'"
  local bundle="\`git -C $quoted bundle create $name --all\`"
  if (($7)) && [[ -z $2 ]]; then
    text=$bundle
    (($3 || $4)) && text="commit the uncommitted and untracked work and each stash (a bundle holds commits only), then $bundle"
  elif (($7)); then
    remote=origin
    grep -qx origin <<<"$2" || remote=$(head -n 1 <<<"$2")
    (($3)) && steps='commit the uncommitted and untracked work'
    (($4)) && steps="${steps:+$steps, }turn each stash into a branch (\`git stash branch <name>\`)"
    (($5)) && steps="${steps:+$steps, }put the commits on no branch on a branch or tag"
    if [[ -z $steps && -n $6 ]]; then
      text="\`git -C $quoted push $remote$6\`"
    elif [[ -n $steps && -n $6 ]]; then
      text="$steps, then push what holds them, and \`git -C $quoted push $remote$6\`"
    elif [[ -n $steps ]]; then
      text="$steps, then push the branch or tag that holds them"
    else
      text=$bundle
    fi
  fi
  (($8)) && text="${text:+$text; }back up the ignored files \`--backup-paths\` lists"
  echo "next: $text"
}

repo_count=0
repo_clean=0

report_repo() { # <label> <main work tree or bare repository> <work|bare>
  local findings line
  repo_count=$((repo_count + 1))
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
# submodule, or `--separate-git-dir`, a file), every bare-repository candidate,
# and every `.env`-style file.
walk() {
  find "${walk_roots[@]}" \( -path "$home_real/Library/Caches" -o -path "$home_real/.Trash" -o -name .cache -o -name node_modules -o -path '*/nix/store' \) -prune \
    -o -name .git -print -prune -o -name HEAD -type f -print \
    -o \( -name .env -o -name '.env.*' -o -name .envrc -o -name .dev.vars \) ! -type d -print 2>/dev/null
}

repo_list=''
seen_repos=''
env_files=''

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

repo_ignored_files() { # every repository's ignored files
  local dir kind worktree
  while IFS=$'\t' read -r dir kind; do
    [[ -n $dir ]] || continue
    while IFS= read -r worktree; do
      [[ -d $worktree ]] && ignored_files "$worktree"
    done < <(worktrees_of "$dir" "$kind")
  done <<<"$repo_list"
  return 0
}

# Every file that cannot be re-created, credential-named ones included. A
# directory is given as its files, so that a credential-named file inside it
# can be taken out.
backup_candidates() {
  local dir folders=(Downloads Pictures)
  ((desktop_documents_synced)) || folders=(Desktop Documents Downloads Pictures)
  for dir in "$claude_dir"/projects/*/memory "$notes_dir" "${folders[@]/#/$HOME/}"; do
    [[ -d $dir ]] && find "$dir" \( -name .git -o -name node_modules -o -name .cache \) -prune -o ! -type d -print 2>/dev/null
  done
  repo_ignored_files
}

# What cannot be re-created and is not a credential, one absolute path per line
# for `tar -T -`. What it leaves out, the report lists under Credentials.
backup_paths() {
  local dir
  backup_candidates | grep -viE "$credential_name" | LC_ALL=C sort -u
  echo 'Files whose name suggests a credential are left out; the report names each one under Credentials.' >&2
  for dir in "${ATUIN_HOME:-}" "$HOME/.local/share/atuin" "$HOME/.atuin"; do
    [[ -n $dir && -d $dir ]] || continue
    echo "atuin history is left out: \`$(tilde "$dir")\` also holds atuin's key. Export it with \`atuin history list --format '{time} {command}' >atuin-history.txt\` and back that file up." >&2
    break
  done
  return 0
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

# The attribute names in the `with pkgs; [ ... ]` list, read from the file:
# evaluating it fetches the pinned nixpkgs from GitHub when the local fetcher
# cache lacks it, even with --offline.
nix_names=$(awk '/with pkgs; \[/ { inside = 1; next } inside && /\]/ { exit } inside { sub(/#.*/, ""); for (i = 1; i <= NF; i++) print $i }' "$repo_dir/nix/packages.nix" 2>/dev/null)
if [[ -n $nix_names ]]; then
  nix_state='items whose name matches a package name in `nix/packages.nix` are marked; the names are read from the file, so a command named unlike its package (for example `rg` for `ripgrep`) is not marked'
else
  nix_state='no package name could be read from `nix/packages.nix`: no item is marked as covered'
fi

nix_covers() { [[ -n $nix_names ]] && grep -qxF -- "$1" <<<"$nix_names"; }

while IFS= read -r path; do
  case $path in
    */.git) add_repo "${path%/.git}" work ;;
    */HEAD) add_repo "${path%/HEAD}" bare ;;
    *) env_files=$env_files$path$'\n' ;;
  esac
done < <(walk)
if [[ ${1:-} == --backup-paths ]]; then
  backup_paths
  exit 0
fi

printf '# Pre-wipe inventory\n\n'
printf 'What wiping this machine would lose. Generated %s on %s, read-only: the script writes nothing and runs no fetch. Each item marked **needs action** is something to save, push, or confirm before the wipe; credential locations show names, counts, and sizes only.\n\n' "$(date '+%Y-%m-%d %H:%M')" "$(uname -s)"
printf -- '- HOME: `%s`\n- ghq roots: %s\n- agent notes: `%s`\n- what to back up: run with `--backup-paths` for one path per line, for `tar -T -`\n' "$HOME" "$(while IFS= read -r root; do printf '`%s` ' "$(tilde "$root")"; done <<<"$ghq_roots")" "$(tilde "$notes_dir")"
have ghq || note 'ghq: not installed'

section 'Git repositories' 'commit and push, or bundle, what each listed repository holds; each one ends with a next step. Commit counts compare with the remote refs from the last fetch, so run `git fetch` in a repository first if its remote may have moved. Untracked files honour .gitignore; ignored files are listed when no build re-creates them and their name suggests no secret.'
note "Searched \`~\` and every ghq root for work trees (a \`.git\` directory or file) and bare repositories, skipping $prune_list; symlinks are not followed. Each submodule and each linked worktree's repository is checked as a repository of its own."
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
note "\`.env\` files (also \`.env.*\`, \`.envrc\`, \`.dev.vars\`) the repository walk reached, except tracked ones and \`.env.example\`, \`.env.sample\`, and \`.env.template\`, and each file \`--backup-paths\` leaves out because its name suggests a secret:"
found=0
while IFS= read -r file; do
  [[ -n $file ]] || continue
  git_ro -C "${file%/*}" ls-files --error-unmatch -- "${file##*/}" >/dev/null 2>&1 && continue
  found=1
  needs_action "$(describe_location "$file")"
done < <({ printf '%s' "$env_files" | sed -E '/\.env\.(example|sample|template)$/d'; backup_candidates | grep -iE "$credential_name"; } | LC_ALL=C sort -u)
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
# colima and lima keep each VM's disk on this machine whether it runs or not.
# A VM is a directory holding lima.yaml, so it is found without running either.
found=0
for vm in "${LIMA_HOME:-$HOME/.lima}"/*/lima.yaml "${COLIMA_HOME:-$HOME/.colima}"/_lima/*/lima.yaml; do
  [[ -f $vm ]] || continue
  found=1
  vm=${vm%/lima.yaml}
  needs_action "lima VM \`${vm##*/}\` in \`$(tilde "${vm%/*}")\`: $(size_of "$vm")"
done
((found)) || note 'colima and lima: no VM in `~/.colima/_lima` or `~/.lima`'

section 'Local databases' 'dump each listed data directory (for example `pg_dumpall`, `mysqldump`, or a Redis snapshot) before the wipe.'
# The prefix is the directory the brew on PATH sits in, so finding it runs no brew.
brew_prefix=''
have brew && brew_prefix=$(command -v brew) && brew_prefix=${brew_prefix%/bin/brew}
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
  subsection 'Homebrew services (`homebrew.mxcl.*` launchd plists)'
  found=0
  for plist in "$HOME"/Library/LaunchAgents/homebrew.mxcl.*.plist /Library/LaunchDaemons/homebrew.mxcl.*.plist; do
    [[ -e $plist ]] || continue
    found=1
    listed "\`${plist##*/}\`"
  done
  ((found)) || note 'none'
fi

section 'Installed software' "reinstall each listed item on the new machine, or add it to the dotfiles. Items marked as in \`nix/packages.nix\` come back with the first switch. Marking: $nix_state. Casks and App Store apps are never marked: that list holds CLI packages, and a cask can share a command's name."

# <mark> is "nix" to mark items that nix/packages.nix covers, "apps" not to.
software() { # <title> <mark> <why there is nothing to read, or empty> <sed -E -n program> <command>...   one item per line; its first word names the package
  local title=$1 mark=$2 absent=$3 program=$4 out line name
  shift 4
  subsection "$title"
  if [[ -n $absent ]]; then
    note "$absent"
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

not_installed() { have "$1" || echo "$1: not installed"; }

entries() { # <path>...   the name of each one that exists
  local entry
  for entry in "$@"; do
    [[ -e $entry ]] && printf '%s\n' "${entry##*/}"
  done
  return 0
}

node_packages() { # <node_modules dir>...   a scoped package as @scope/name
  local dir entry
  for dir in "$@"; do
    for entry in "$dir"/* "$dir"/@*/*; do
      [[ -d $entry && ${entry##*/} != @* ]] && printf '%s\n' "${entry#"$dir"/}"
    done
  done
  return 0
}

# Package managers are read from the files they keep rather than run: run on a
# fresh HOME they fetch indexes, migrate state, or write logs. npm and uv are
# asked only for a directory.
brew_formulae() { # installed on request: what `brew leaves` approximates
  { grep -l '"installed_on_request": *true' "$brew_prefix"/Cellar/*/*/INSTALL_RECEIPT.json 2>/dev/null || [[ $? == 1 ]]; } |
    awk -F/ '{ print $(NF - 2) }' | LC_ALL=C sort -u
}

devbox_json=${XDG_DATA_HOME:-$HOME/.local/share}/devbox/global/default/devbox.json
devbox_packages() {
  if have jq; then
    jq -r '.packages | if type == "array" then .[] else keys[] end' "$devbox_json"
  else
    # Without jq, one quoted package per line, the layout devbox writes.
    sed -n '/"packages"/,/]/p' "$devbox_json" | sed -E -n 's/^[[:space:]]*"([^"]+)",?[[:space:]]*$/\1/p'
  fi
}

npm_packages() {
  local dir
  dir=$(npm_config_logs_max=0 npm root -g 2>/dev/null) && node_packages "$dir"
}

if [[ -n ${PNPM_HOME:-} ]]; then
  pnpm_home=$PNPM_HOME
elif [[ $(uname -s) == Darwin ]]; then
  pnpm_home=$HOME/Library/pnpm
else
  pnpm_home=${XDG_DATA_HOME:-$HOME/.local/share}/pnpm
fi

uv_tools() {
  local dir
  dir=$(UV_NO_CACHE=1 uv tool dir 2>/dev/null) && entries "$dir"/*
}

cargo_home=${CARGO_HOME:-$HOME/.cargo}
cargo_crates() {
  if [[ -f $cargo_home/.crates2.json ]]; then
    { grep -oE '"[^" ]+ [^" ]+ \([^"]*\)":' "$cargo_home/.crates2.json" || [[ $? == 1 ]]; } | sed -E 's/^"([^ ]+) ([^ ]+).*/\1 \2/'
  else
    entries "$cargo_home"/bin/*
  fi
}

mise_installs=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/installs
mise_tools() { # <tool> <version>; a symlink is a version alias such as `latest`
  local install tool
  for install in "$mise_installs"/*/*; do
    [[ -d $install && ! -L $install ]] || continue
    tool=${install%/*}
    printf '%s %s\n' "${tool##*/}" "${install##*/}"
  done
  return 0
}

brew_absent=''
[[ -n $brew_prefix ]] || brew_absent='brew: not installed'
devbox_absent=''
[[ -f $devbox_json ]] || devbox_absent="devbox: no global \`devbox.json\` at \`$(tilde "$devbox_json")\`"
pnpm_absent=''
[[ -d $pnpm_home/global ]] || pnpm_absent="pnpm: no global packages in \`$(tilde "$pnpm_home")/global\`"
cargo_absent=''
[[ -f $cargo_home/.crates2.json || -d $cargo_home/bin ]] || cargo_absent="cargo: no installed crates in \`$(tilde "$cargo_home")\`"
mise_absent=''
[[ -d $mise_installs ]] || mise_absent="mise: no installs in \`$(tilde "$mise_installs")\`"

mas_names='s/^[0-9]+[[:space:]]+//; s/[[:space:]]+\([^)]*\)[[:space:]]*$//; p'
software 'Homebrew formulae installed on request (`Cellar`)' nix "$brew_absent" p brew_formulae
software 'Homebrew casks (`Caskroom`)' apps "$brew_absent" p entries "$brew_prefix"/Caskroom/*
software '`mas list`' apps "$(not_installed mas)" "$mas_names" mas list
software "devbox global packages (\`$(tilde "$devbox_json")\`)" nix "$devbox_absent" p devbox_packages
software 'global npm packages (`npm root -g`)' nix "$(not_installed npm)" p npm_packages
software "global pnpm packages (\`$(tilde "$pnpm_home")/global\`)" nix "$pnpm_absent" p node_packages "$pnpm_home"/global/*/node_modules
software 'uv tools (`uv tool dir`)' nix "$(not_installed uv)" p uv_tools
software "cargo crates (\`$(tilde "$cargo_home")\`)" nix "$cargo_absent" p cargo_crates
software "mise installs (\`$(tilde "$mise_installs")\`)" nix "$mise_absent" p mise_tools

subsection 'Apps in `/Applications` from neither Homebrew nor the App Store'
if [[ ! -d /Applications ]]; then
  note '`/Applications`: not found'
else
  # A cask's version directory links to the app it installed; a cask whose
  # directory holds no link is recognised by its token alone.
  cask_tokens=''
  cask_apps=''
  if [[ -n $brew_prefix ]]; then
    cask_tokens=$(entries "$brew_prefix"/Caskroom/*)
    cask_apps=$(entries "$brew_prefix"/Caskroom/*/*/*.app)
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
where='System Settings > your name > iCloud > iCloud Drive > Desktop & Documents Folders'
if ((desktop_documents_synced)); then
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
