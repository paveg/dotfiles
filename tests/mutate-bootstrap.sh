#!/usr/bin/env bash
# Break one condition of scripts/bootstrap.sh, or of the step list in
# spec/bootstrap.tla, at a time; tests/bootstrap.sh must fail the checks named
# for it. uname is a stub there, and DOTFILES_TEST_ROOT stands in for the Nix
# profile and systemd, so every mutant is caught on any OS.
# No mutant drops the stubs from the front of PATH after the Nix profile loads,
# or DOTFILES_TEST_ROOT from the paths it stands in for: on a machine with Nix,
# that copy would run the real nix.
# SC2016: each mutation target is literal source text, not an expansion.
# shellcheck disable=SC2016
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/mutate.sh
source "$repo_dir/tests/lib/mutate.sh"

# Copies of the script and the model, with <file> broken by each <old> <new>
# pair in turn.
run_mutant() { # <dir> <check>... <file> <old> <new> [<old> <new>]...
  local dir=$1 checks=$2 file=$3 out
  shift 3
  cp "$repo_dir/scripts/bootstrap.sh" "$repo_dir/spec/bootstrap.tla" "$dir/"
  while (($# >= 2)); do
    mutate_apply "$dir/$file" "$1" "$2" || return
    shift 2
  done
  out=$("$repo_dir/tests/bootstrap.sh" "$dir/bootstrap.sh" "$dir/bootstrap.tla" 2>&1) || true
  mutate_has_summary "$out" || return
  # shellcheck disable=SC2086 # one check name per word
  mutate_checks_failed "$out" $checks
}

# Copies of the script and the model, <file> changed when one is given; succeeds
# when every check passes.
run_passing() { # <dir> [<file> <old> <new>]
  cp "$repo_dir/scripts/bootstrap.sh" "$repo_dir/spec/bootstrap.tla" "$1/"
  if (($# == 4)); then mutate_apply "$1/$2" "$3" "$4" || return; fi
  "$repo_dir/tests/bootstrap.sh" "$1/bootstrap.sh" "$1/bootstrap.tla" >/dev/null 2>&1
}

expect_caught() { # <check>... <description> <file> <old> <new> [<old> <new>]...
  mutant "$2" run_mutant "$1" "${@:3}"
}

macs='personal-mac work-mac'
all='personal-mac work-mac wsl'
each() { # <hosts> <suffix>: "<host>-<suffix>" for each host
  local host
  for host in $1; do printf '%s-%s ' "$host" "$2"; done
}

mutate_inputs scripts/bootstrap.sh spec/bootstrap.tla hosts/wsl.nix profiles/work.example \
  tests/bootstrap.sh tests/mutate-bootstrap.sh tests/lib/
mutate_baseline 'the script and the model as committed' "$repo_dir/tests/bootstrap.sh"
# A copy layout the test cannot run in would count every mutant as caught.
clean_mutant 'an unmutated copy passes its tests' run_passing

S=bootstrap.sh
expect_caught 'no-host-refused unknown-host-refused' 'a missing or unknown host is accepted' $S \
  '    say "usage: bootstrap.sh <host>, where <host> is personal-mac, work-mac or wsl"
    exit 2' '    want=Darwin'
expect_caught 'no-host-refused unknown-host-refused' 'a refused host exits 1' $S \
  '    exit 2
    ;;' '    exit 1
    ;;'
expect_caught 'wrong-os-refused wrong-os-refused-on-linux' 'the OS is not checked' $S \
  'if [[ $(uname -s) != "$want" ]]; then' 'if false; then'
expect_caught unrecorded-host-refused 'the recorded host is not compared' $S \
  '    if [[ $recorded != "$host" ]]; then' '    if false; then'
expect_caught dangling-host-link-refused 'a dangling host link counts as no host' $S \
  'if [[ -s $host_file || -L $host_file ]]; then' 'if [[ -s $host_file ]]; then'
expect_caught xdg-config-home-holds-the-host 'the host file ignores XDG_CONFIG_HOME' $S \
  'host_file=${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host' 'host_file=$HOME/.config/dotfiles/host'
expect_caught "$(each "$all" records-the-host)" 'the host is not recorded' $S \
  '    mv -f "$host_file.new" "$host_file"' '    rm -f "$host_file.new"'
expect_caught "$(each "$all" rerun-changes-nothing)" 'every run appends the host again' $S \
  'if [[ ! -s $host_file ]]; then' 'if true; then' \
  '    mv -f "$host_file.new" "$host_file"' '    cat "$host_file.new" >>"$host_file"
    rm "$host_file.new"'
expect_caught a-run-killed-recording-the-host-leaves-none 'the host file is written in place' $S \
  '"$host" >"$host_file.new"
    mv -f "$host_file.new" "$host_file"' '"$host" >"$host_file"'
expect_caught an-empty-host-file-counts-as-none 'an empty host file refuses the run' $S \
  'if [[ -s $host_file || -L $host_file ]]; then' 'if [[ -e $host_file || -L $host_file ]]; then'
expect_caught an-empty-host-file-counts-as-none 'an empty host file is kept' $S \
  'if [[ ! -s $host_file ]]; then' 'if [[ ! -e $host_file ]]; then'
expect_caught "$(each "$all" home-gains-only-allowlisted-entries)" 'the script writes a file of its own below HOME' $S \
  'StepRecordHost() {' 'StepRecordHost() {
  : >"$HOME/.bootstrap-state"'
expect_caught "$(each "$all" home-gains-only-allowlisted-entries)" 'the script keeps a file beside the checkout' $S \
  '  cd "$checkout"' '  cd "$checkout"
  : >"$HOME/repos/.bootstrap-state"'

expect_caught "$(each "$all" waits-at-StepSignIn-with-the-host-recorded) personal-mac-waits-at-StepSignIn-then-refuses-work-mac" \
  'the host is recorded in the last step' $S \
  'StepRecordHost() {' 'StepRecordHost() { :; }

record_host() {' \
  'StepInstallHooks() {' 'StepInstallHooks() {
  record_host'
expect_caught 'a-switch-exiting-75-fails-the-run-with-1 failed-switch-then-refuses-work-mac' \
  'the host is recorded after the first switch' $S \
  'StepRecordHost() {' 'StepRecordHost() { :; }

record_host() {' \
  'StepFirstSwitch() { switch; }' 'StepFirstSwitch() {
  switch
  record_host
}'
expect_caught 'a-switch-exiting-75-fails-the-run-with-1 mise-exiting-2-fails-the-run-with-1' \
  "a failed command's status is the run's" $S "trap 'exit 1' ERR" ':'
expect_caught 'a-switch-exiting-75-fails-the-run-with-1 mise-exiting-2-fails-the-run-with-1' \
  'the ERR trap is not inherited by the steps' $S 'set -Eeuo pipefail' 'set -euo pipefail'
waiting_runs='personal-mac-waits-at-StepSignIn work-mac-waits-at-StepWorkProfile wsl-waits-at-StepGhtknAuth'
expect_caught "$(each "$waiting_runs" gaining-only-allowlisted-entries)" 'a waiting run writes a file below HOME' $S \
  '  say "waiting for a person: $1' '  : >"$HOME/.bootstrap-waiting"
  say "waiting for a person: $1'
expect_caught "$(each "$waiting_runs" after-the-steps-before-it)" 'a waiting run calls ksm' $S \
  '  say "waiting for a person: $1' '  ksm secret list
  say "waiting for a person: $1'
expect_caught 'personal-mac-waits-at-StepSignIn-without-a-work-profile wsl-waits-at-StepGhtknAuth-without-a-work-profile' \
  'a waiting run creates ~/.config/dots-work/' $S \
  '  say "waiting for a person: $1' '  mkdir -p "$work_profile"
  say "waiting for a person: $1'
expect_caught 'work-mac-waits-at-StepWorkProfile-after-the-steps-before-it' 'work-mac switches before its profile is placed' $S \
  'StepWorkProfile() {' 'StepWorkProfile() {
  switch' \
  'StepSecondSwitch() {
  switch' 'StepSecondSwitch() {
  :'
expect_caught 'personal-mac-waits-at-StepSignIn work-mac-waits-at-StepWorkProfile wsl-waits-at-StepGhtknAuth personal-mac-stops-on-upstream-nix' \
  'the waiting status is 1' $S 'waiting=75' 'waiting=1'
expect_caught 'personal-mac-waits-at-StepSignIn work-mac-waits-at-StepWorkProfile wsl-waits-at-StepGhtknAuth' \
  'a human step does not check its result' $S 'until "$@" >/dev/null 2>&1; do' 'until true; do'
expect_caught 'personal-mac-waits-at-StepSignIn work-mac-waits-at-StepWorkProfile wsl-waits-at-StepGhtknAuth' \
  'a human step with no terminal goes on' $S '      wait_for_person "$what"' '      break'
expect_caught "$(each "$macs" waits-at-StepSignIn)" 'the 1Password agent socket is not checked' $S \
  'else [[ -S $agent_socket ]]; fi' 'else true; fi'
expect_caught 'wsl-waits-at-StepSignIn wsl-runs-the-expected-commands' 'ssh-add.exe is not asked for a key' $S \
  'then ssh-add.exe -l; else' 'then true; else'
expect_caught "$(each "$all" waits-at-StepGhtknAuth)" 'ghtkn is not checked' $S 'ghtkn exec -- true' 'true'

expect_caught 'personal-mac-finishes wsl-finishes' 'the work profile step runs on every host' $S \
  'if [[ $host == work-mac ]]; then' 'if true; then'
expect_caught work-mac-waits-at-StepWorkProfile 'the work profile is not waited for' $S \
  'test -d "$work_profile"' 'true'
expect_caught 'personal-mac-has-no-work-profile wsl-has-no-work-profile' 'every host creates ~/.config/dots-work/' $S \
  'StepWorkProfile() {' 'StepWorkProfile() {
  mkdir -p "$work_profile"'
expect_caught 'personal-mac-never-calls-ksm wsl-never-calls-ksm' 'every host calls ksm' $S \
  'StepWorkProfile() {' 'StepWorkProfile() {
  ksm secret list'

expect_caught wsl-with-nix-command-off-waits 'nix-command is not checked' $S \
  'elif ! nix eval --expr 1 >/dev/null; then' 'elif false; then'
expect_caught "$(each "$macs" stops-on-upstream-nix)" 'upstream Nix on a Mac goes on' $S \
  '! command -v determinate-nixd' 'false'
expect_caught wsl-goes-on-with-upstream-nix 'upstream Nix on wsl waits for Determinate Nix' $S \
  'elif [[ $host != wsl ]] && ! command -v determinate-nixd' 'elif true && ! command -v determinate-nixd'
expect_caught work-mac-stops-on-upstream-nix 'upstream Nix stops only personal-mac' $S \
  'elif [[ $host != wsl ]] && ! command -v determinate-nixd' 'elif [[ $host == personal-mac ]] && ! command -v determinate-nixd'
refused='no-host-refused unknown-host-refused wrong-os-refused wrong-os-refused-on-linux unrecorded-host-refused'
expect_caught "$refused" 'Nix is installed before the host is checked' $S \
  'StepCheckHost() {
  local want recorded' 'StepCheckHost() {
  local want recorded
  command -v nix >/dev/null || curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm'
expect_caught wsl-without-systemd-waits 'Nix is installed on wsl without systemd' $S \
  'if [[ $host == wsl && ! -d $test_root/run/systemd/system ]]; then' 'if false; then'
expect_caught personal-mac-installs-determinate-nix 'every host needs systemd for the install' $S \
  '[[ $host == wsl && ! -d $test_root/run/systemd/system ]]' '[[ ! -d $test_root/run/systemd/system ]]'
expect_caught personal-mac-installs-determinate-nix 'the installer is not run' $S \
  '    curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm' '    :'
expect_caught personal-mac-installs-determinate-nix 'the Nix profile is not loaded after the install' $S \
  '--no-confirm
    load_nix' '--no-confirm'
expect_caught "$(each "$all" finishes)" 'Nix is installed when it is already there' $S \
  '  if ! command -v nix >/dev/null; then' '  if true; then'
expect_caught "$(each "$all" finishes)" 'the clone ignores GHQ_ROOT' $S '  GHQ_ROOT=$HOME/repos nix shell' '  nix shell'
expect_caught "$(each "$all" keeps-what-was-there)" 'the clone replaces an existing checkout' $S \
  '  GHQ_ROOT=$HOME/repos nix shell' '  rm -rf "$checkout"
  GHQ_ROOT=$HOME/repos nix shell'
expect_caught 'work-mac-keeps-what-was-there work-mac-rerun-keeps-what-was-there' \
  'the work profile step writes over a profile file' $S \
  'test -d "$work_profile"' 'test -d "$work_profile"
    echo {} >"$work_profile/claude/settings.work.json"'
expect_caught "$(each "$all" runs-the-expected-commands)" 'the steps after the clone run outside the checkout' $S \
  '  cd "$checkout"' '  :'
expect_caught "$(each "$macs" runs-the-expected-commands)" 'the Mac switch runs without sudo' $S \
  '    sudo nix run nix-darwin' '    nix run nix-darwin'
expect_caught "$(each "$macs" puts-the-profile-on-path-behind-the-stubs)" 'the Mac switch leaves the per-user profile off PATH' $S \
  '    path_prepend "/etc/profiles/per-user/$(id -un)/bin"' '    :'
# On a Mac switched to this repository, that directory holds the real ghtkn,
# mise and lefthook, which the copy would run ahead of the stubs.
[[ ! -d /etc/profiles/per-user/$(id -un)/bin ]] ||
  mutate_host_lacks="this host has /etc/profiles/per-user/$(id -un)/bin, whose real tools that copy would run"
expect_caught "$(each "$macs" puts-the-profile-on-path-behind-the-stubs)" 'the per-user profile goes ahead of the stubs' $S \
  '    path_prepend "/etc/profiles/per-user/$(id -un)/bin"' '    PATH=/etc/profiles/per-user/$(id -un)/bin:$PATH'
mutate_host_lacks=
expect_caught wsl-puts-the-profile-on-path-behind-the-stubs 'the wsl switch leaves ~/.nix-profile/bin off PATH' $S \
  '    path_prepend "$HOME/.nix-profile/bin"' '    :'
expect_caught 'wsl-finishes wsl-puts-the-profile-on-path-behind-the-stubs' 'the stubs are left behind the profile after the wsl switch' $S \
  '    path_prepend "$HOME/.nix-profile/bin"' '    PATH=$HOME/.nix-profile/bin:$PATH'
expect_caught "$(each "$all" runs-the-expected-commands)" 'the second switch is skipped' $S \
  'StepSecondSwitch() {
  switch' 'StepSecondSwitch() {
  :'
expect_caught "$(each "$all" installs-runtimes-after-the-last-switch)" 'mise install is not run' $S \
  '  mise install' '  :'
expect_caught "$(each "$all" installs-runtimes-after-the-last-switch)" 'mise install runs before the second switch' $S \
  '  switch
  mise install' '  mise install
  switch'
expect_caught 'a-checkout-without-lefthook-config-gets-no-hooks a-checkout-without-lefthook-config-is-kept' \
  'lefthook install runs without a lefthook.yml' $S 'if [[ -f lefthook.yml ]]; then' 'if true; then'
expect_caught "$(each "$all" runs-the-expected-commands)" 'the git hooks are not installed' $S \
  '    lefthook install' '    :'

expect_caught "$(each "$all" takes-the-model-steps)" 'a step only in the script' $S \
  "StepGhtknAuth StepInstallHooks'" "StepGhtknAuth StepInstallHooks StepExtra'" \
  'main() {' 'StepExtra() { :; }

main() {'
expect_caught "$(each "$all" takes-the-model-steps) $(each "$all" runs-the-expected-commands)" \
  'a step function runs outside the step list' $S \
  '  for step in $steps; do' '  StepExtra
  for step in $steps; do' \
  'main() {' 'StepExtra() { :; }

main() {'
expect_caught "$(each "$all" takes-the-model-steps)" 'a step only in the model' bootstrap.tla \
  '\/ StepGhtknAuth \/ StepInstallHooks' '\/ StepGhtknAuth \/ StepInstallHooks \/ StepExtra'
expect_caught "$(each "$all" takes-the-model-steps)" 'two steps swap places in the script' $S \
  'StepSignIn StepWorkProfile' 'StepWorkProfile StepSignIn'
clean_mutant 'the step banner is reworded' run_passing $S 'say "step $n: $step"' 'say "[$n/10] $step"'
mutate_finish
