#!/usr/bin/env bash
# Set up this machine as <host> from paveg/dotfiles (docs/design.md, Bootstrap).
# Each step is a function named after its step action in spec/bootstrap.tla and
# runs in the model's order. Every step is safe to rerun, so a run that stopped
# resumes with the same command.
# Usage: curl -fsSL https://raw.githubusercontent.com/paveg/dotfiles/main/scripts/bootstrap.sh | bash -s -- <host>
#        scripts/bootstrap.sh <host>     (<host>: personal-mac, work-mac or wsl)
# Exit:  0 finished; 2 the host is missing or does not fit this machine, and
#        nothing changed; 75 waiting for a person: do what the last line says,
#        then run the same command again; 1 a step failed, whatever status the
#        command that failed returned, so 2 and 75 mean only the above.
# Env:   DOTFILES_TEST_STUB_DIR, set only by tests, goes first on PATH after
#        every PATH change, so a stub always wins over the real command.
#        DOTFILES_TEST_ROOT, set only by tests, stands for / in the two paths
#        the script probes the machine with, the Nix profile and systemd's
#        directory, so the test machine's own Nix and systemd decide nothing.
# Runs on macOS's bash 3.2. Everything is in functions and main runs on the
# last line, so a download cut short runs nothing.
set -Eeuo pipefail
trap 'exit 1' ERR

steps='StepCheckHost StepInstallNix StepRecordHost StepClone StepFirstSwitch
  StepSignIn StepWorkProfile StepSecondSwitch StepGhtknAuth StepInstallHooks'
waiting=75
host_file=${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host
checkout=$HOME/repos/github.com/paveg/dotfiles
work_profile=$HOME/.config/dots-work
test_root=${DOTFILES_TEST_ROOT-}
nix_profile=$test_root/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
agent_socket="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

say() { printf 'bootstrap: %s\n' "$*" >&2; }

wait_for_person() { # <what to do>
  say "waiting for a person: $1, then run the same command again"
  exit "$waiting"
}

stubs_first() {
  if [[ -n ${DOTFILES_TEST_STUB_DIR-} ]]; then PATH=$DOTFILES_TEST_STUB_DIR:$PATH; fi
}

path_prepend() { # <dir>
  PATH=$1:$PATH
  stubs_first
}

# A person's step: until <check> passes, ask on the terminal and wait for Enter.
# With no terminal, as in CI, stop with the waiting status instead of hanging.
human() { # <what to do> <check>...
  local what=$1
  shift
  until "$@" >/dev/null 2>&1; do
    { printf 'bootstrap: %s, then press Enter ' "$what" >/dev/tty && read -r _ </dev/tty; } 2>/dev/null ||
      wait_for_person "$what"
  done
}

StepCheckHost() {
  local want recorded
  case $host in
  personal-mac | work-mac) want=Darwin ;;
  wsl) want=Linux ;;
  *)
    say "usage: bootstrap.sh <host>, where <host> is personal-mac, work-mac or wsl"
    exit 2
    ;;
  esac
  if [[ $(uname -s) != "$want" ]]; then
    say "$host runs on $want, and this machine runs $(uname -s)"
    exit 2
  fi
  # An empty file records no host. A link is left alone even when dangling.
  if [[ -s $host_file || -L $host_file ]]; then
    recorded=$(cat "$host_file" 2>/dev/null) || recorded='(unreadable)'
    if [[ $recorded != "$host" ]]; then
      say "$host_file records $recorded; changing a machine's host is done by hand (docs/design.md, Bootstrap)"
      exit 2
    fi
  fi
}

load_nix() {
  # shellcheck source=/dev/null
  if [[ -f $nix_profile ]]; then . "$nix_profile"; fi
  stubs_first
}

StepInstallNix() {
  load_nix
  if ! command -v nix >/dev/null; then
    if [[ $host == wsl && ! -d $test_root/run/systemd/system ]]; then
      wait_for_person "turn on systemd: put '[boot] systemd=true' in /etc/wsl.conf and run 'wsl --shutdown' from Windows"
    fi
    curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
    load_nix
  elif [[ $host != wsl ]] && ! command -v determinate-nixd >/dev/null; then
    wait_for_person "this Mac runs upstream Nix; install Determinate Nix from its macOS package (docs/design.md, Bootstrap)"
  fi
}

# Written beside the file and renamed into place, so a run stopped at any point
# leaves the host recorded in full or not at all for just switch, which reads
# it; the next run overwrites a leftover copy.
StepRecordHost() {
  if [[ ! -s $host_file ]]; then
    mkdir -p "${host_file%/*}"
    printf '%s\n' "$host" >"$host_file.new"
    mv -f "$host_file.new" "$host_file"
  fi
}

# No git is assumed on the host and no SSH key exists yet: HTTPS, with git and
# ghq from nixpkgs. On an existing checkout ghq prints "exists" and runs no git.
StepClone() {
  GHQ_ROOT=$HOME/repos nix shell nixpkgs#git nixpkgs#ghq -c ghq get https://github.com/paveg/dotfiles
  cd "$checkout"
}

switch() {
  local user
  if [[ $host == wsl ]]; then
    user=$(nix eval --raw --file hosts/wsl.nix user)
    nix run home-manager -- switch --flake ".#$user@wsl"
    path_prepend "$HOME/.nix-profile/bin"
  else
    sudo nix run nix-darwin -- switch --flake ".#$host"
    path_prepend "/etc/profiles/per-user/$(id -un)/bin"
  fi
}

StepFirstSwitch() { switch; }

signed_in() {
  if [[ $host == wsl ]]; then ssh-add.exe -l; else [[ -S $agent_socket ]]; fi
}

StepSignIn() {
  human "sign in to the 1Password app and turn on its SSH agent and CLI integration" signed_in
}

# work-mac only, and only the hand-placed path of ADR 0002: the Keeper pull
# needs scripts/work-sync.sh. It never writes the profile, so a rerun cannot
# overwrite unpushed edits.
StepWorkProfile() {
  if [[ $host == work-mac ]]; then
    human "place the work profile in ~/.config/dots-work/ (ADR 0002)" test -d "$work_profile"
  fi
}

# spec/bootstrap.tla has no action for mise install: it is part of the last switch.
StepSecondSwitch() {
  switch
  mise install
}

StepGhtknAuth() {
  human "run 'ghtkn agent unlock --enable-refresh', then 'ghtkn auth' once per app" ghtkn exec -- true
}

# lefthook install writes an example lefthook.yml into a checkout that has none
# (measured, lefthook 2.2.2), which a later pull of the real one would trip on.
StepInstallHooks() {
  if [[ -f lefthook.yml ]]; then
    lefthook install
  else
    say "the checkout has no lefthook.yml yet, so there are no git hooks to install"
  fi
  if [[ $host == wsl ]]; then
    say "by hand on Windows: winget install --id Microsoft.WindowsTerminal -e; winget install --id StablyAI.Orca -e; winget install raycast; then import the .rayconfig from 1Password"
  else
    say "by hand: approve Karabiner-Elements in System Settings, add Raycast's script directory, and import the .rayconfig from 1Password (none on a first machine)"
  fi
}

main() {
  local step n=0
  host=${1-}
  if [[ -n ${DOTFILES_TEST_STUB_DIR-} ]]; then
    say "test stubs from $DOTFILES_TEST_STUB_DIR come first on PATH"
    stubs_first
  fi
  for step in $steps; do
    n=$((n + 1))
    say "step $n: $step"
    "$step"
  done
  say "done: this machine is set up as $host"
}

main "$@"
