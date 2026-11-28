#!/usr/bin/env bash
# Check the git files in <home-dir> (default home/) in a temporary HOME, with no
# Nix switch: a repository resolves the personal identity and signing key, and
# one under the work org's directory, spelled in either case or reached through
# a symlinked ~/repos, or a linked worktree of one wherever it lives, resolves
# the work profile's, and commits are signed through 1Password's signer for
# the OS. Work repositories, and only they, ask ghtkn for HTTPS credentials on
# GitHub, with the repository owner, ahead of any system helper, and the work
# ghtkn.yaml defines the app gh-app names and gives it the work org's pushes.
# The work side comes from <work-profile-dir> (default
# profiles/work.example/), placed where the work profile lives on work-mac.
# tests/packages.sh checks that the built configuration links these files.
# Repositories are set up with no global config, so only the queries read the
# files under test. git ships no switch for this, so the check without a work
# profile has no mutant: git itself is what ignores the missing include.
# Usage: tests/git.sh [home-dir] [work-profile-dir]
# Env: GIT_BIN overrides the git to test.
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
home_src=${1:-$repo_dir/home}
profile_src=${2:-$repo_dir/profiles/work.example}
git_bin=${GIT_BIN:-$(command -v git)}
# The org directory that profiles/work.example/ names, and the same name in
# the other case that ghq keeps when the clone URL spells it that way.
work_org=example-org
work_org_other_case=Example-Org

# The physical path, as a real HOME is: on macOS mktemp's /var is a symlink,
# and git compares a PWD-named path with ~ resolved to the physical HOME.
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
work_dir=$(cd "$work_dir" && pwd -P)

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

is() { # <name> <want> <got>
  if [[ $3 == "$2" ]]; then ok "$1"; else fail "$1" "want '$2', got '$3'"; fi
}

# The git files that nix/home.nix links, under the names it links them to:
# <platform>.gitconfig (darwin or wsl) becomes platform.gitconfig.
new_home() { # <name> <platform>
  local home=$work_dir/$1 file
  mkdir -p "$home/.config/git"
  for file in config ignore personal.gitconfig; do
    cp "$home_src/.config/git/$file" "$home/.config/git/$file" 2>/dev/null || :
  done
  cp "$home_src/.config/git/$2.gitconfig" "$home/.config/git/platform.gitconfig" 2>/dev/null || :
  echo "$home"
}

add_work_profile() { # <home>
  mkdir -p "$1/.config/dots-work"
  cp -R "$profile_src/." "$1/.config/dots-work/"
}

# The files under test: the global config in <home>, nothing from /etc. With
# with_pwd set, PWD names the directory as reached, as an interactive shell
# sets it; git then matches includeIf against that path, not only the
# physical one.
git_at() { # <home> <dir> <git-arg>...
  local home=$1 dir=$2
  shift 2
  (cd "$dir" && env -i HOME="$home" PATH=/usr/bin:/bin GIT_CONFIG_NOSYSTEM=1 \
    ${with_pwd:+"PWD=$PWD"} "$git_bin" "$@")
}

# Setup only: no global config at all, so creating a repository depends on
# none of the files under test.
git_setup() { # <dir> <git-arg>...
  local dir=$1
  shift
  (cd "$dir" && env -i HOME="$work_dir" PATH=/usr/bin:/bin GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null "$git_bin" -c user.name=setup -c user.email=setup@example.invalid \
    "$@") >/dev/null 2>&1
}

make_repo() { # <dir>
  mkdir -p "$1"
  git_setup "$1" init -q && git_setup "$1" commit -q --allow-empty -m init
}

add_worktree() { # <repo> <worktree-dir> <branch>
  mkdir -p "$(dirname "$2")"
  git_setup "$1" worktree add -q -b "$3" "$2"
}

# Each identity is read four ways: from <dir> and through git -C from <home>,
# each without PWD (as env -i runs git) and with it, as a shell sets it.
identity_is() { # <name> <home> <dir> <want-name> <want-email> <want-signing-key>
  local name=$1 home=$2 dir=$3 suffix field got with_pwd
  local -a want=("$4" "$5" "$6") keys=(user.name user.email user.signingkey) labels=(name email signing-key)
  for suffix in '' -pwd -C -C-pwd; do
    with_pwd=
    [[ $suffix == *pwd ]] && with_pwd=1
    for field in 0 1 2; do
      if [[ $suffix == -C* ]]; then
        got=$(git_at "$home" "$home" -C "$dir" config --get "${keys[field]}" 2>&1)
      else
        got=$(git_at "$home" "$dir" config --get "${keys[field]}" 2>&1)
      fi
      is "$name-${labels[field]}$suffix" "${want[field]}" "$got"
    done
  done
}

file_value() { # <file> <key>
  "$git_bin" config --file "$1" --get "$2" 2>/dev/null
}

personal_name=$(file_value "$home_src/.config/git/personal.gitconfig" user.name)
personal_email=$(file_value "$home_src/.config/git/personal.gitconfig" user.email)
work_name=$(file_value "$profile_src/git/work.gitconfig" user.name)
work_email=$(file_value "$profile_src/git/work.gitconfig" user.email)
personal_key=$(file_value "$home_src/.config/git/personal.gitconfig" user.signingkey)
work_key=$(file_value "$profile_src/git/work.gitconfig" user.signingkey)
# An identity that is missing on both sides would compare equal.
if [[ -n $personal_name && -n $personal_email ]]; then
  ok personal-identity-set
else
  fail personal-identity-set "personal.gitconfig gives name '$personal_name', email '$personal_email'"
fi
if [[ -n $work_name && -n $work_email && $work_email != "$personal_email" ]]; then
  ok work-identity-set
else
  fail work-identity-set "work.gitconfig gives name '$work_name', email '$work_email'"
fi
# Without its own key, a work commit is signed with the personal key, which
# GitHub shows as Unverified when the work email belongs to another account.
if [[ -n $work_key && $work_key != "$personal_key" ]]; then
  ok work-signing-key-set
else
  fail work-signing-key-set "work.gitconfig gives user.signingkey '$work_key'"
fi

home=$(new_home work-host darwin)
add_work_profile "$home"
org_dir=$home/repos/github.com/$work_org
work_repo=$org_dir/app
personal_repo=$home/repos/github.com/paveg/dotfiles
make_repo "$work_repo"
make_repo "$personal_repo"
# Where Claude Code puts its worktrees, somewhere outside the org directory,
# and a personal repository's worktree that sits inside the org directory.
add_worktree "$work_repo" "$work_repo/.claude/worktrees/agent" agent
add_worktree "$work_repo" "$home/elsewhere/app-wt" outside
add_worktree "$personal_repo" "$org_dir/dotfiles-wt" stray
if [[ -d $work_repo/.claude/worktrees/agent && -d $home/elsewhere/app-wt && -d $org_dir/dotfiles-wt ]]; then
  ok setup-repositories
else
  fail setup-repositories "git could not create the repositories under $home"
fi

work=("$work_name" "$work_email" "$work_key")
personal=("$personal_name" "$personal_email" "$personal_key")
identity_is work-repo "$home" "$work_repo" "${work[@]}"
identity_is work-worktree-inside "$home" "$work_repo/.claude/worktrees/agent" "${work[@]}"
identity_is work-worktree-outside "$home" "$home/elsewhere/app-wt" "${work[@]}"
identity_is personal-repo "$home" "$personal_repo" "${personal[@]}"
# The include follows the repository, not the directory the worktree sits in.
identity_is personal-worktree-in-org-dir "$home" "$org_dir/dotfiles-wt" "${personal[@]}"
identity_is outside-any-repo "$home" "$home" "${personal[@]}"

# ghq keeps the clone URL's case, and GitHub org names ignore case, so the
# org directory on disk may differ in case from the profile's pattern.
mixed=$(new_home mixed-case-host darwin)
add_work_profile "$mixed"
make_repo "$mixed/repos/github.com/$work_org_other_case/app"
identity_is org-dir-other-case "$mixed" "$mixed/repos/github.com/$work_org_other_case/app" "${work[@]}"
# Where the file system ignores case (APFS by default), the same repository
# can also be reached under the pattern's spelling.
if [[ -d $mixed/repos/github.com/$work_org/app ]]; then
  identity_is org-dir-other-case-reached-as-pattern "$mixed" "$mixed/repos/github.com/$work_org/app" "${work[@]}"
fi

# ~/repos kept on another volume behind a symlink: without PWD, git sees only
# the physical path, which does not start with ~/repos.
linked=$(new_home symlinked-repos-host darwin)
add_work_profile "$linked"
mkdir -p "$work_dir/volume/repos"
ln -s "$work_dir/volume/repos" "$linked/repos"
make_repo "$work_dir/volume/repos/github.com/$work_org/app"
identity_is repos-behind-symlink "$linked" "$linked/repos/github.com/$work_org/app" "${work[@]}"

# Agent worktrees stay out of every repository's status.
if git_at "$home" "$personal_repo" check-ignore -q .claude/worktrees/agent/file; then
  ok ignore-claude-worktrees
else
  fail ignore-claude-worktrees "the global ignore does not cover .claude/worktrees/"
fi
is ghq-root '~/repos' "$(git_at "$home" "$home" config --get ghq.root 2>&1)"

# A personal host has no work profile: the include of the missing file is
# ignored, and a repository under the org directory stays personal.
bare=$(new_home personal-host wsl)
make_repo "$bare/repos/github.com/$work_org/app"
identity_is no-profile-org-repo "$bare" "$bare/repos/github.com/$work_org/app" "${personal[@]}"
if out=$(git_at "$bare" "$bare" config --list 2>&1); then
  ok no-profile-config-reads
else
  fail no-profile-config-reads "$(tr '\n' ' ' <<<"$out" | cut -c1-200)"
fi

# Commits are signed with an SSH key that 1Password holds, through its signer:
# a program in the app on macOS, the Windows signer on wsl, which also hands
# ssh to Windows. Nothing is signed here; this reads what a commit would use.
config_at() { # <home> <dir> <key>
  git_at "$1" "$2" config --get "$3" 2>&1
}
for platform in darwin wsl; do
  case $platform in
  darwin) at=$home repo=$personal_repo ;;
  wsl) at=$bare repo=$bare/repos/github.com/$work_org/app ;;
  esac
  is "signing-format-$platform" ssh "$(config_at "$at" "$repo" gpg.format)"
  is "signing-commits-$platform" true "$(config_at "$at" "$repo" commit.gpgsign)"
  # The public key itself, which 1Password matches to its private key, rather
  # than the path of a key file on disk.
  key=$(config_at "$at" "$repo" user.signingkey)
  if [[ $key == "ssh-ed25519 "* ]]; then
    ok "signing-key-is-public-key-$platform"
  else
    fail "signing-key-is-public-key-$platform" "user.signingkey is '$key'"
  fi
done
is signing-program-darwin /Applications/1Password.app/Contents/MacOS/op-ssh-sign \
  "$(config_at "$home" "$personal_repo" gpg.ssh.program)"
is signing-program-darwin-work-repo /Applications/1Password.app/Contents/MacOS/op-ssh-sign \
  "$(config_at "$home" "$work_repo" gpg.ssh.program)"
# A bare name, so the path holds no Windows user name; that the Windows PATH
# finds it is Unverified (docs/design.md).
is signing-program-wsl op-ssh-sign-wsl.exe \
  "$(config_at "$bare" "$bare/repos/github.com/$work_org/app" gpg.ssh.program)"
is ssh-command-darwin "" "$(config_at "$home" "$personal_repo" core.sshCommand)"
is ssh-command-wsl ssh.exe "$(config_at "$bare" "$bare/repos/github.com/$work_org/app" core.sshCommand)"

# Work repositories fetch and push over HTTPS with a ghtkn token, through the
# helper the work profile sets, and nothing else asks ghtkn. A stub ghtkn
# first on PATH records what git sends it and answers with a fake password.
stub_dir=$work_dir/stub
helper_log=$work_dir/ghtkn-helper.log
mkdir -p "$stub_dir"
cat >"$stub_dir/ghtkn" <<STUB
#!/bin/sh
echo "args: \$*" >'$helper_log'
cat >>'$helper_log'
echo username=x-access-token
echo password=stub-ghtkn-password
STUB
chmod +x "$stub_dir/ghtkn"
# What git asks the helpers before a fetch or push, with no terminal to fall
# back on; the password line is what it would send. <system-config> stands in
# for a system gitconfig, such as Apple's, which sets a helper of its own.
password_for() { # <home> <dir> <host> <path> [<system-config>]
  local system_config=(GIT_CONFIG_NOSYSTEM=1)
  [[ -n ${5-} ]] && system_config=(GIT_CONFIG_SYSTEM="$5")
  rm -f "$helper_log"
  printf 'protocol=https\nhost=%s\npath=%s\n\n' "$3" "$4" |
    (cd "$2" && env -i HOME="$1" PATH="$stub_dir:/usr/bin:/bin" GIT_TERMINAL_PROMPT=0 "${system_config[@]}" \
      "$git_bin" credential fill 2>/dev/null) | sed -n 's/^password=//p'
}
helper_calls() {
  if [[ -e $helper_log ]]; then tr '\n' ' ' <"$helper_log" | sed 's/ $//'; fi
}

is work-credential-from-ghtkn stub-ghtkn-password "$(password_for "$home" "$work_repo" github.com "$work_org/app.git")"
# With useHttpPath, ghtkn gets the owner that ghtkn.yaml's git_owners maps to
# the write app; without it, the read app GHTKN_APP names.
is work-credential-sends-owner \
  "args: git-credential get protocol=https host=github.com path=$work_org/app.git" "$(helper_calls)"
printf '[credential]\n  helper = "!f() { echo username=decoy; echo password=decoy-password; }; f"\n' \
  >"$work_dir/system-helper.gitconfig"
is work-credential-drops-system-helper stub-ghtkn-password \
  "$(password_for "$home" "$work_repo" github.com "$work_org/app.git" "$work_dir/system-helper.gitconfig")"
is work-credential-other-host-skips-ghtkn "" \
  "$(password_for "$home" "$work_repo" gitlab.example.com "$work_org/app.git")$(helper_calls)"
is personal-credential-skips-ghtkn "" \
  "$(password_for "$home" "$personal_repo" github.com paveg/dotfiles.git)$(helper_calls)"

# The app gh uses is defined, and pushes to the work org get that same write
# app through git_owners.
work_ghtkn=$profile_src/ghtkn/ghtkn.yaml
gh_app=$(cat "$profile_src/ghtkn/gh-app" 2>/dev/null)
if [[ -n $gh_app ]] && grep -qxF "  - name: $gh_app" "$work_ghtkn"; then
  ok work-ghtkn-gh-app-defined
else
  fail work-ghtkn-gh-app-defined "gh-app names '$gh_app', which $work_ghtkn does not define"
fi
owner_app=$(awk -v org="$work_org" '
  /^  - name: / { name = $3; owners = 0; next }
  /^    git_owners:/ { owners = 1; next }
  owners && /^      - / { if ($2 == org) print name; next }
  { owners = 0 }' "$work_ghtkn" 2>&1)
is work-ghtkn-push-app "$gh_app" "$owner_app"

echo "summary: $checks checks, $failures failed (git $("$git_bin" --version), home $home_src)"
if ((failures > 0)); then exit 1; fi
