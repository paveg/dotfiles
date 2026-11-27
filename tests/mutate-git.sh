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

# shellcheck source=tests/lib/mutate.sh
source "$repo_dir/tests/lib/mutate.sh"

# <file> is relative to a copy holding home/ and profile/ (the work profile).
run_mutant() { # <dir> <check>... <file> <old> <new>
  local dir=$1 checks=$2 file=$3 old=$4 new=$5 out
  cp -R "$repo_dir/home" "$dir/home"
  cp -R "$repo_dir/profiles/work.example" "$dir/profile"
  mutate_apply "$dir/$file" "$old" "$new" || return
  out=$("$repo_dir/tests/git.sh" "$dir/home" "$dir/profile" 2>&1) || true
  mutate_has_summary "$out" || return
  # shellcheck disable=SC2086 # one check name per word
  mutate_checks_failed "$out" $checks
}

# macOS's file system folds case and its temporary directory sits behind a
# symlink, so the mutants graded by the case and symlink checks run there too.
expect_caught() { # <check>... <description> <file> <old> <new>
  if [[ $1 =~ other-case|behind-symlink ]]; then
    local mutate_runs_on='linux macos'
  fi
  mutant "$2" run_mutant "$1" "$3" "$4" "$5"
}

config=home/.config/git/config
include=profile/git/include.gitconfig
work_include=$'[include]\n  path = ~/.config/dots-work/git/include.gitconfig\n'
personal_include=$'[include]\n  path = ~/.config/git/personal.gitconfig\n'
platform_include=$'[include]\n  path = ~/.config/git/platform.gitconfig\n'
condition='"gitdir/i:github.com/example-org/"'

# tests/git.sh reads each identity four ways; a mutant must fail all of them.
all_modes() { # <check>...
  local check
  for check; do printf '%s ' "$check" "$check-pwd" "$check-C" "$check-C-pwd"; done
}

# tests/git.sh reaches the mixed-case org directory under the pattern's
# spelling only where the file system ignores case.
mkdir "$mutate_dir/Fold"
folded_never_included= folded_key_missing= folded_case_kept=
if [[ -d $mutate_dir/fold ]]; then
  folded_never_included=$(all_modes org-dir-other-case-reached-as-pattern-name org-dir-other-case-reached-as-pattern-email)
  folded_key_missing=$(all_modes org-dir-other-case-reached-as-pattern-signing-key)
  # git matches the pattern's spelling when PWD names it.
  folded_case_kept='org-dir-other-case-reached-as-pattern-email org-dir-other-case-reached-as-pattern-email-C
    org-dir-other-case-reached-as-pattern-email-C-pwd'
fi

mutate_inputs home profiles/work.example tests/git.sh tests/mutate-git.sh tests/lib/
mutate_baseline 'the files as committed' "$repo_dir/tests/git.sh"

expect_caught "$(all_modes personal-repo-name personal-repo-email personal-worktree-in-org-dir-name \
  outside-any-repo-name outside-any-repo-email no-profile-org-repo-name no-profile-org-repo-email \
  personal-worktree-in-org-dir-signing-key outside-any-repo-signing-key no-profile-org-repo-signing-key)" \
  'the personal identity is never included' \
  "$config" "$personal_include" ''

expect_caught personal-identity-set 'the personal identity has no email' \
  home/.config/git/personal.gitconfig '  email = pavegy@gmail.com' ''

expect_caught work-identity-set 'the example work identity is the personal one' \
  profile/git/work.gitconfig 'email = work@example.com' 'email = pavegy@gmail.com'

expect_caught "work-signing-key-set $(all_modes work-repo-signing-key work-worktree-inside-signing-key \
  work-worktree-outside-signing-key org-dir-other-case-signing-key repos-behind-symlink-signing-key) \
  $folded_key_missing" \
  'the example work profile sets no signing key, so work commits are signed with the personal one' \
  profile/git/work.gitconfig '  signingkey = ssh-ed25519 AAAAPLACEHOLDER-work-signing-public-key' ''

expect_caught "$(all_modes work-repo-name work-repo-email work-worktree-inside-name work-worktree-inside-email \
  work-worktree-outside-name work-worktree-outside-email org-dir-other-case-name org-dir-other-case-email \
  repos-behind-symlink-name repos-behind-symlink-email) $folded_never_included" \
  'the work profile is never included' \
  "$config" "$work_include" ''

expect_caught "$(all_modes work-repo-email work-worktree-inside-email work-worktree-outside-email \
  work-repo-signing-key)" \
  'the work profile is included before the personal identity, which then wins' \
  "$config" "$personal_include$platform_include$work_include" "$work_include$personal_include$platform_include"

expect_caught "$(all_modes work-repo-email work-worktree-outside-email)" \
  'the work profile is included from a path the profile does not use' \
  "$config" '~/.config/dots-work/git/include.gitconfig' '~/.config/dots-work/include.gitconfig'

expect_caught "$(all_modes personal-repo-email personal-worktree-in-org-dir-email outside-any-repo-email \
  personal-repo-signing-key personal-worktree-in-org-dir-signing-key outside-any-repo-signing-key)" \
  'the work identity is included for every repository' \
  "$config" '~/.config/dots-work/git/include.gitconfig' '~/.config/dots-work/git/work.gitconfig'

expect_caught "$(all_modes work-repo-email work-worktree-inside-email work-worktree-outside-email)" \
  'the org directory pattern has no trailing slash, so it matches no repository below it' \
  "$include" 'example-org/"]' 'example-org"]'

expect_caught "$(all_modes work-worktree-inside-email work-worktree-outside-email)" \
  'the condition matches only a main checkout'"'"'s .git, which no linked worktree has as its gitdir' \
  "$include" "$condition" '"gitdir/i:github.com/example-org/*/.git"'

expect_caught "$(all_modes work-repo-email work-worktree-inside-email work-worktree-outside-email)" \
  'the condition is a branch name, which says nothing about where a repository lives' \
  "$include" "$condition" '"onbranch:example-org/"'

expect_caught "$(all_modes org-dir-other-case-name org-dir-other-case-email) $folded_case_kept" \
  'the condition keeps case, so an org directory cloned as Example-Org stays personal' \
  "$include" "$condition" '"gitdir:github.com/example-org/"'

# With PWD naming ~/repos, git matches the anchored pattern on that path.
expect_caught 'repos-behind-symlink-email repos-behind-symlink-email-C repos-behind-symlink-email-C-pwd' \
  'the condition is anchored at ~/repos, which git -C and a run without PWD see only as its physical path' \
  "$include" "$condition" '"gitdir/i:~/repos/github.com/example-org/"'

expect_caught ignore-claude-worktrees 'the global ignore leaves agent worktrees in git status' \
  home/.config/git/ignore $'.claude/worktrees/\n' ''

expect_caught ignore-claude-worktrees 'the global ignore is read from somewhere else' \
  "$config" 'excludesFile = ~/.config/git/ignore' 'excludesFile = ~/.config/git/ignore.missing'

expect_caught ghq-root 'ghq clones somewhere other than ~/repos' \
  "$config" 'root = ~/repos' 'root = ~/ghq'

darwin=home/.config/git/darwin.gitconfig
wsl=home/.config/git/wsl.gitconfig

expect_caught 'signing-format-darwin signing-format-wsl' 'git signs with gpg rather than an SSH key' \
  "$config" $'[gpg]\n  format = ssh\n' ''

expect_caught 'signing-commits-darwin signing-commits-wsl' 'commits are not signed unless asked' \
  "$config" 'gpgsign = true' 'gpgsign = false'

expect_caught 'signing-key-is-public-key-darwin signing-key-is-public-key-wsl' \
  'the signing key is a key file on disk' \
  home/.config/git/personal.gitconfig \
  'signingkey = ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC3c+G4Y5+gaeYYtfSQUE/7p4RtsQdfrKi4a8aRiN4Wn' \
  'signingkey = ~/.ssh/id_ed25519.pub'

expect_caught 'signing-program-darwin signing-program-darwin-work-repo signing-program-wsl ssh-command-wsl' \
  'the platform file is never included' \
  "$config" "$platform_include" ''

expect_caught 'signing-program-darwin signing-program-darwin-work-repo' 'macOS signs with plain ssh-keygen instead of the 1Password signer' \
  "$darwin" 'program = /Applications/1Password.app/Contents/MacOS/op-ssh-sign' 'program = ssh-keygen'

expect_caught signing-program-wsl 'wsl signs with the Linux side, where 1Password has no agent' \
  "$wsl" '  program = op-ssh-sign-wsl.exe' ''

expect_caught ssh-command-wsl 'wsl runs the Linux ssh, which cannot reach 1Password on Windows' \
  "$wsl" '  sshCommand = ssh.exe' ''

expect_caught ssh-command-darwin 'macOS hands ssh to a Windows binary' \
  "$darwin" '[gpg "ssh"]' $'[core]\n  sshCommand = ssh.exe\n[gpg "ssh"]'

mutate_finish
