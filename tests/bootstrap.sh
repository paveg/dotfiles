#!/usr/bin/env bash
# Run scripts/bootstrap.sh the way `curl ... | bash -s -- <host>` does, in
# throwaway homes under `env -i`, with a PATH that starts with a stub for every
# command it calls. A human step's stub makes its check pass, uname's stub picks
# the OS, and DOTFILES_TEST_ROOT, a directory of the case's, stands for / in the
# Nix profile and systemd paths the script probes, so every host runs on any
# runner and the runner's own Nix never runs. Each run is detached from the
# terminal, so a human step stops instead of asking. A trace sourced through
# BASH_ENV logs each Step* function the script enters, in order with the stubs'
# calls.
# Checks:
# - a complete run enters spec/bootstrap.tla's step actions in the model's
#   order and no other Step* function, runs the expected commands, mise install
#   last of them, with the switched profile on PATH behind the stubs, and
#   records the host, below XDG_CONFIG_HOME when that is set;
# - neither it nor a second run changes an existing checkout or the
#   hand-placed work profile, and the second changes nothing below $HOME, link
#   targets included; $HOME gains only the recorded host, the checkout, and
#   what the stub nix writes; a checkout without lefthook.yml gets no hooks;
# - a missing, unknown, wrong-OS or unrecorded host, or a dangling host link,
#   exits 2 having run only the host check and changed nothing, with no Nix
#   installed;
# - without nix a Mac runs Determinate's installer and goes on with the nix it
#   installed, and wsl without systemd waits; upstream Nix stops each Mac, and
#   wsl only with nix-command off;
# - a command that fails with 75 or 2 fails the run with 1; an empty host file
#   records no host, and a run killed while recording the host leaves none;
# - with one human step undone the run exits 75 at that step, having run the
#   steps before it and no more, recorded the host so that a rerun naming the
#   other Mac is refused, and added only allowed entries, and it finishes once
#   the step is done;
# - personal hosts never call ksm or create ~/.config/dots-work/.
# Usage: tests/bootstrap.sh [script [spec]]   (mutant copies may be given)
# SC2016: the stub lines and the perl launcher are source for another shell or
#         for perl, expanded when they run. SC2088: the ~ in the expected calls
#         is the log's notation for HOME.
# shellcheck disable=SC2016,SC2088
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
script=${1:-$repo_dir/scripts/bootstrap.sh}
spec=${2:-$repo_dir/spec/bootstrap.tla}
bare_path=/usr/bin:/bin:/usr/sbin:/sbin
base_path=/nix/var/nix/profiles/default/bin:$bare_path
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

is() { # <name> <want> <got>
  if [[ $3 == "$2" ]]; then ok "$1"; else fail "$1" "want '$2', got '$3'"; fi
}

# A stub that appends "<cwd, with HOME as ~> <name> <args>" to the case's log,
# then runs the body on stdin. The case directory is written into it, so it
# needs nothing from the environment `env -i` clears and logs from anywhere.
stub() { # <name> <body
  {
    echo '#!/bin/sh'
    echo "case_dir='$case_dir'"
    echo "echo \"~\${PWD#\"\$HOME\"} $1 \$*\" >>\"\$case_dir/log\""
    cat
  } >"$stubs/$1"
  chmod +x "$stubs/$1"
}

# Sourced through BASH_ENV before the script: appends "step <name>" to the log
# on entry to any function named Step*, so a step run outside the step list
# shows too. The depth of FUNCNAME tells an entry from the function's later
# commands.
trace() { # >file
  echo 'set -T'
  echo "trap 'if [[ -z \${FUNCNAME[0]-} ]]; then trace_depth=0; else
  if ((\${#FUNCNAME[@]} > trace_depth)) && [[ \${FUNCNAME[0]} == Step* ]]; then echo \"step \${FUNCNAME[0]}\" >>\"$log\"; fi
  trace_depth=\${#FUNCNAME[@]}; fi' DEBUG"
}

# A fresh case: a throwaway HOME, a stub for every command the script calls,
# and no human step done. A human step's command is stubbed even then, failing
# as it does before the person acts: the script puts the switched profile on
# PATH, and on a bootstrapped Mac that holds the real ghtkn. The stub nix
# writes below HOME what the real one does: `nix shell` the cache in
# ~/.cache/nix (measured by a review agent), and the home-manager switch the
# ~/.nix-profile link to ~/.local/state/nix/profiles/profile (the layout nix
# 2.33.0 creates, measured). That profile holds decoys, so a stub left behind
# ~/.nix-profile/bin on PATH is seen.
new_case() { # <name> <host>
  local os=Darwin name
  [[ $2 != wsl ]] || os=Linux
  case_dir=$work_dir/$1
  home=$case_dir/home stubs=$case_dir/stubs log=$case_dir/log
  bash_env=$case_dir/trace.bash file_limit='' path=$stubs:$base_path run_env=''
  mkdir -p "$home" "$stubs" "$case_dir/decoys/bin"
  trace >"$bash_env"
  printf '#!/bin/sh\necho %s\n' "$os" >"$stubs/uname"
  chmod +x "$stubs/uname"
  stub nix <<'SH'
if [ -e "$case_dir/nix-command-off" ]; then
  echo "error: experimental Nix feature 'nix-command' is disabled" >&2
  exit 1
fi
case $1 in
shell)
  mkdir -p "$HOME/.cache/nix"
  while [ "$1" != -c ]; do shift; done
  shift
  exec "$@"
  ;;
eval) if [ "$2" = --expr ]; then echo 1; else echo ryota; fi ;;
run)
  if [ "$2" = home-manager ]; then
    mkdir -p "$HOME/.local/state/nix/profiles"
    ln -sfn "$case_dir/decoys" "$HOME/.local/state/nix/profiles/profile"
    ln -sfn "$HOME/.local/state/nix/profiles/profile" "$HOME/.nix-profile"
  fi
  ;;
esac
SH
  stub sudo <<<'exec "$@"'
  stub ghq <<'SH'
checkout=${GHQ_ROOT:?}/github.com/paveg/dotfiles
if [ -d "$checkout" ]; then echo exists; exit 0; fi
mkdir -p "$checkout" && : >"$checkout/lefthook.yml"
SH
  stub curl <<<'exit 1'
  stub op <<<'exit 1'
  # ADR 0004: 111 is ghtkn's exit for a locked or unauthenticated agent.
  stub ghtkn <<<'exit 111'
  stub ssh-add.exe <<<'echo "The agent has no identities." >&2; exit 1'
  for name in determinate-nixd ksm; do stub "$name" </dev/null; done
  stub mise <<<'echo "$PATH" >"$case_dir/mise-path"'
  # lefthook install writes an example lefthook.yml where there is none, as
  # 2.2.2 does (docs/design.md, Bootstrap step 10).
  stub lefthook <<<'[ "$1" != install ] || [ -f lefthook.yml ] || echo "# example" >lefthook.yml'
  for name in mise ghtkn lefthook; do
    printf '#!/bin/sh\necho "decoy %s $*" >>"%s"\nexit 1\n' "$name" "$log" >"$case_dir/decoys/bin/$name"
    chmod +x "$case_dir/decoys/bin/$name"
  done
}

# No nix, as on a fresh machine: the case's PATH loses the default Nix
# profile, the stub nix moves out, and curl serves an installer that logs its
# arguments, puts the stub at the default profile below the case's root, and
# writes the profile script that adds it to PATH, where Determinate's
# installer puts its own. Should a copy of the script load the machine's own
# Nix profile instead, its once-per-shell guard makes it add nothing.
without_nix() {
  local profile=$case_dir/root/nix/var/nix/profiles/default
  path=$stubs:$bare_path run_env=__ETC_PROFILE_NIX_SOURCED=1
  mv "$stubs/nix" "$case_dir/nix"
  {
    echo "echo \"~\${PWD#\"\$HOME\"} installer \$*\" >>'$log'"
    echo "mkdir -p '$profile/bin' '$profile/etc/profile.d'"
    echo "mv '$case_dir/nix' '$profile/bin/nix'"
    echo "echo 'PATH=$profile/bin:\$PATH' >'$profile/etc/profile.d/nix-daemon.sh'"
  } >"$case_dir/installer"
  stub curl <<<"cat '$case_dir/installer'"
}

# The human steps each host waits for, by the step that checks them.
human_steps() { # <host>
  case $1 in
  work-mac) echo StepSignIn StepWorkProfile StepGhtknAuth ;;
  *) echo StepSignIn StepGhtknAuth ;;
  esac
}

# Do the person's part of <step> for <host>, as the stubs CI uses: a socket at
# the 1Password agent path on a Mac (bound from inside its directory, whose path
# is longer than a socket address may be), an ssh-add.exe that lists a key on
# wsl, the example work profile, and a ghtkn that succeeds.
do_human_step() { # <host> <step>
  local socket_dir="$home/Library/Group Containers/2BUA8C4S2C.com.1password/t"
  case $2 in
  StepSignIn)
    if [[ $1 == wsl ]]; then
      stub ssh-add.exe <<<"echo '256 SHA256:stub stub-key (ED25519)'"
    else
      mkdir -p "$socket_dir"
      (cd "$socket_dir" && /usr/bin/perl -MIO::Socket::UNIX -e \
        'IO::Socket::UNIX->new(Local => "agent.sock", Listen => 1) or die "socket: $!\n"')
    fi
    ;;
  StepWorkProfile)
    mkdir -p "$home/.config"
    cp -R "$repo_dir/profiles/work.example" "$home/.config/dots-work"
    ;;
  StepGhtknAuth) stub ghtkn </dev/null ;;
  esac
}

do_human_steps() { # <host> [<step to leave undone>]
  local step
  for step in $(human_steps "$1"); do
    [[ $step == "${2-}" ]] || do_human_step "$1" "$step"
  done
}

# Run the script from HOME, piped in as from curl, under env -i, in a new
# session with no controlling terminal, with the case's PATH, BASH_ENV and
# extra variables and, when set, its limit on the size of a file written. Sets
# status and out, and empties the log first.
run() { # <arg>...
  local launcher='if (my $pid = fork) { waitpid $pid, 0; exit($? & 127 ? 128 + ($? & 127) : $? >> 8) }
    POSIX::setsid(); exec @ARGV or die "exec: $!\n"'
  : >"$log"
  status=0
  # shellcheck disable=SC2086 # run_env holds one assignment per word
  out=$(cd "$home" && { [[ -z $file_limit ]] || ulimit -f "$file_limit"; } && cat "$script" |
    env -i HOME="$home" PATH="$path" DOTFILES_TEST_STUB_DIR="$stubs" DOTFILES_TEST_ROOT="$case_dir/root" BASH_ENV="$bash_env" \
      $run_env /usr/bin/perl -MPOSIX -e "$launcher" /bin/bash -s -- "$@" 2>&1) || status=$?
}

steps_run() { sed -n 's/^step //p' "$log"; }
last_step() { steps_run | tail -n 1; }
log_lines() { tr '\n' ';' <"$log"; }
recorded() { cat "$home/.config/dotfiles/host" 2>/dev/null || echo none; }
work_profile_state() { if [[ -e $home/.config/dots-work ]]; then echo present; else echo absent; fi; }

# A log up to the end of <step>'s part.
log_through() { # <step> <log
  awk -v step="step $1" 'seen && /^step / { exit } $0 == step { seen = 1 } { print }'
}

# Each path below HOME, or below <dir> in it, with its type and mode, a link's
# target and a regular file's checksum.
snapshot() { # [<dir>]
  (cd "$home" && find "./${1-}" | LC_ALL=C sort | while IFS= read -r path; do
    sum=
    if [[ -L $path ]]; then
      sum="-> $(readlink "$path")"
    elif [[ -f $path ]]; then
      sum=$(cksum <"$path")
    fi
    # shellcheck disable=SC2012 # the mode string, which BSD and GNU stat print differently
    echo "$(ls -ld "$path" | cut -c1-10) $path $sum"
  done)
}

paths() { (cd "$home" && find . | LC_ALL=C sort); }

kept_state() { # the snapshot of each directory in $kept
  local dir
  for dir in $kept; do snapshot "$dir"; done
}

# A checkout made before the run, with a local file and each <file>; the stub
# ghq then finds it and clones nothing.
seed_checkout() { # <file>...
  local checkout=$home/repos/github.com/paveg/dotfiles file
  mkdir -p "$checkout"
  echo 'edits of my own' >"$checkout/notes.local"
  for file; do echo "# $file" >"$checkout/$file"; done
}

# What a run may add below HOME: the recorded host, the checkout, and what the
# stub nix writes there.
allowed='\./\.config
\./\.config/dotfiles
\./\.config/dotfiles/host
\./\.cache
\./\.cache/nix(/.*)?
\./\.local
\./\.local/state
\./\.local/state/nix
\./\.local/state/nix/profiles(/[^/]+)?
\./\.nix-profile
\./repos
\./repos/github\.com
\./repos/github\.com/paveg
\./repos/github\.com/paveg/dotfiles(/.*)?'

# The first entry of the PATH mise ran with, and its first that is not the
# stubs: this reads the PATH the script hands its commands, not what the
# profile directory holds, which takes a real switch.
path_heads() {
  tr ':' '\n' <"$case_dir/mise-path" | awk -v stubs="$stubs" 'NR == 1 { first = $0 } $0 != stubs && other == "" { other = $0 }
    END { print first, other }'
}

# The paths below HOME that are new since <before> and not allowed.
gained() { # <before>
  LC_ALL=C comm -13 <(echo "$1") <(paths) | grep -vxE -f <(echo "$allowed") | tr '\n' ' ' || true
}

# The step actions of Next's Steps disjunction, ordered by the pc each one
# requires.
model_steps() {
  local names name pc
  names=$(sed -n '/^Steps ==/,/^$/p' "$spec" | grep -oE 'Step[A-Z][A-Za-z]*') || names=
  for name in $names; do
    pc=$(sed -n "/^$name ==/,/^\$/p" "$spec" | grep -oE 'pc = [0-9]+' | head -n 1) || pc=
    echo "${pc#pc = } $name"
  done | sort -n | cut -d' ' -f2
}

# The log of a complete run: each step as it is entered, then the commands it
# runs.
expected_log() { # <host>
  local co='~/repos/github.com/paveg/dotfiles' switch
  if [[ $1 == wsl ]]; then
    switch="$co nix eval --raw --file hosts/wsl.nix user
$co nix run home-manager -- switch --flake .#ryota@wsl"
  else
    switch="$co sudo nix run nix-darwin -- switch --flake .#$1
$co nix run nix-darwin -- switch --flake .#$1"
  fi
  echo 'step StepCheckHost'
  echo 'step StepInstallNix'
  echo '~ nix eval --expr 1'
  echo 'step StepRecordHost'
  echo 'step StepClone'
  echo '~ nix shell nixpkgs#git nixpkgs#ghq -c ghq get https://github.com/paveg/dotfiles'
  echo '~ ghq get https://github.com/paveg/dotfiles'
  echo 'step StepFirstSwitch'
  echo "$switch"
  echo 'step StepSignIn'
  [[ $1 != wsl ]] || echo "$co ssh-add.exe -l"
  echo 'step StepWorkProfile'
  echo 'step StepSecondSwitch'
  echo "$switch"
  echo "$co mise install"
  echo 'step StepGhtknAuth'
  echo "$co ghtkn exec -- true"
  echo 'step StepInstallHooks'
  echo "$co lefthook install"
}

# Exit 2 with only the host check run and nothing below HOME changed.
expect_refused() { # <name> <arg>...
  local name=$1 before changed=unchanged
  shift
  before=$(snapshot)
  run "$@"
  [[ $(snapshot) == "$before" ]] || changed=changed
  is "$name" 'exit 2, log: step StepCheckHost;, home unchanged' "exit $status, log: $(log_lines), home $changed"
}

# Exit 75 at the Nix step, with nothing below HOME changed.
expect_waits_for_nix() { # <name> <host> <log>
  local before changed=unchanged
  before=$(snapshot)
  run "$2"
  [[ $(snapshot) == "$before" ]] || changed=changed
  is "$1" "exit 75 at StepInstallNix, log: $3, home unchanged" "exit $status at $(last_step), log: $(log_lines), home $changed"
}

model=$(model_steps)

if nix=$(env -i PATH="$bare_path" /bin/sh -c 'command -v nix'); then
  echo "ERROR: $nix is on $bare_path, so the cases without nix would run it" >&2
  exit 2
fi

# A fresh case for each, so that what one run wrote cannot refuse the next.
# None has nix, so a Nix install before the host check would show in its log.
new_case no-host personal-mac
without_nix
expect_refused no-host-refused
new_case unknown-host personal-mac
without_nix
expect_refused unknown-host-refused laptop
new_case wrong-os personal-mac
without_nix
expect_refused wrong-os-refused wsl
new_case wrong-os-on-linux wsl
without_nix
expect_refused wrong-os-refused-on-linux personal-mac
new_case unrecorded-host personal-mac
without_nix
mkdir -p "$home/.config/dotfiles"
echo personal-mac >"$home/.config/dotfiles/host"
expect_refused unrecorded-host-refused work-mac
new_case dangling-host-link personal-mac
without_nix
mkdir -p "$home/.config/dotfiles"
ln -s "$home/nowhere" "$home/.config/dotfiles/host"
expect_refused dangling-host-link-refused personal-mac

# With XDG_CONFIG_HOME set, the host is recorded below it, and read from there.
new_case xdg-config-home personal-mac
do_human_steps personal-mac
run_env="XDG_CONFIG_HOME=$home/xdg"
run personal-mac
is xdg-config-home-holds-the-host '0 personal-mac none' \
  "$status $(cat "$home/xdg/dotfiles/host" 2>/dev/null || echo none) $(recorded)"
expect_refused xdg-config-home-refuses-work-mac work-mac

# Without nix, a Mac installs Determinate Nix and goes on with the nix the
# installer put on PATH; wsl without systemd waits for a person first.
new_case personal-mac-without-nix personal-mac
do_human_steps personal-mac
without_nix
run personal-mac
is personal-mac-installs-determinate-nix "0 $(expected_log personal-mac | awk '$0 == "~ nix eval --expr 1" { next } { print }
  $0 == "step StepInstallNix" { print "~ curl -fsSL https://install.determinate.systems/nix"; print "~ installer install --no-confirm" }')" \
  "$status $(cat "$log")"
new_case wsl-without-nix-or-systemd wsl
do_human_steps wsl
without_nix
expect_waits_for_nix wsl-without-systemd-waits wsl 'step StepCheckHost;step StepInstallNix;'

# A command that fails with 75 or 2 must not read as a person's step or a
# refused host. The failed switch also comes after the host is recorded.
new_case failed-switch personal-mac
do_human_steps personal-mac
stub sudo <<<'exit 75'
run personal-mac
is a-switch-exiting-75-fails-the-run-with-1 '1 StepFirstSwitch personal-mac' "$status $(last_step) $(recorded)"
expect_refused failed-switch-then-refuses-work-mac work-mac
new_case failed-mise wsl
do_human_steps wsl
stub mise <<<'exit 2'
run wsl
is mise-exiting-2-fails-the-run-with-1 '1 StepSecondSwitch' "$status $(last_step)"

# An empty host file records no host. A run stopped at its first write to a
# regular file, the host file's, leaves no host file at all. A file size limit
# of 0 sends SIGXFSZ, or fails the write where that signal is ignored. The
# trace is off, and the stub nix the Nix check runs logs nothing, as both
# would write first.
new_case empty-host-file personal-mac
do_human_steps personal-mac
mkdir -p "$home/.config/dotfiles"
: >"$home/.config/dotfiles/host"
run personal-mac
is an-empty-host-file-counts-as-none '0 personal-mac' "$status $(recorded)"
new_case killed-recording-the-host personal-mac
do_human_steps personal-mac
mv "$stubs/nix" "$case_dir/nix"
printf '#!/bin/sh\n' >"$stubs/nix"
chmod +x "$stubs/nix"
bash_env='' file_limit=0
run personal-mac
is a-run-killed-recording-the-host-leaves-none 'stopped none' "$( ((status == 0)) || echo stopped) $(recorded)"
mv "$case_dir/nix" "$stubs/nix"
bash_env=$case_dir/trace.bash file_limit=''
run personal-mac
is a-run-killed-recording-the-host-then-finishes '0 personal-mac' "$status $(recorded)"

# The checkout as it is today has no lefthook.yml: no hooks are installed, and
# nothing is added to it.
new_case no-lefthook-config personal-mac
do_human_steps personal-mac
seed_checkout
kept=repos/github.com/paveg/dotfiles
kept_before=$(kept_state)
run personal-mac
is a-checkout-without-lefthook-config-gets-no-hooks "0 $(expected_log personal-mac | grep -vx '.* lefthook install')" \
  "$status $(cat "$log")"
is a-checkout-without-lefthook-config-is-kept "$kept_before" "$(kept_state)"

# Upstream Nix: each Mac waits for Determinate Nix; wsl goes on with it, unless
# it has nix-command off.
for host in personal-mac work-mac; do
  new_case "$host-with-upstream-nix" "$host"
  do_human_steps "$host"
  rm "$stubs/determinate-nixd"
  expect_waits_for_nix "$host-stops-on-upstream-nix" "$host" 'step StepCheckHost;step StepInstallNix;'
done
new_case wsl-with-upstream-nix wsl
do_human_steps wsl
rm "$stubs/determinate-nixd"
run wsl
is wsl-goes-on-with-upstream-nix "0 $(expected_log wsl)" "$status $(cat "$log")"

# wsl with nix-command off, as upstream Nix has it by default, waits for a
# person instead of failing at the clone.
new_case wsl-with-nix-command-off wsl
do_human_steps wsl
rm "$stubs/determinate-nixd"
: >"$case_dir/nix-command-off"
expect_waits_for_nix wsl-with-nix-command-off-waits wsl 'step StepCheckHost;step StepInstallNix;~ nix eval --expr 1;'

for host in personal-mac work-mac wsl; do
  # A checkout that is already there, with a local file, and on work-mac the
  # hand-placed profile: a run must leave both as they were.
  new_case "$host" "$host"
  do_human_steps "$host"
  seed_checkout lefthook.yml
  kept=repos/github.com/paveg/dotfiles
  [[ $host != work-mac ]] || kept="$kept .config/dots-work"
  kept_before=$(kept_state)
  before=$(paths)
  run "$host"
  is "$host-finishes" 0 "$status"
  [[ $status == 0 ]] || tail -n 5 <<<"$out" | sed 's/^/  /'
  is "$host-takes-the-model-steps" "$model" "$(steps_run)"
  is "$host-runs-the-expected-commands" "$(expected_log "$host")" "$(cat "$log")"
  is "$host-installs-runtimes-after-the-last-switch" 'switch switch mise install ' \
    "$(awk '$2 == "nix" && $3 == "run" { print "switch" } $2 == "mise" { print "mise", $3 }' "$log" | tr '\n' ' ')"
  is "$host-records-the-host" "$host" "$(recorded)"
  profile_bin=/etc/profiles/per-user/$(id -un)/bin
  [[ $host != wsl ]] || profile_bin=$home/.nix-profile/bin
  is "$host-puts-the-profile-on-path-behind-the-stubs" "$stubs $profile_bin" "$(path_heads)"
  is "$host-home-gains-only-allowlisted-entries" '' "$(gained "$before")"
  is "$host-keeps-what-was-there" "$kept_before" "$(kept_state)"
  if [[ $host != work-mac ]]; then
    is "$host-never-calls-ksm" '' "$(awk '$2 == "ksm"' "$log")"
    is "$host-has-no-work-profile" absent "$(work_profile_state)"
  fi

  after=$(snapshot)
  run "$host"
  is "$host-rerun-finishes" 0 "$status"
  is "$host-rerun-changes-nothing" "$after" "$(snapshot)"
  is "$host-rerun-keeps-what-was-there" "$kept_before" "$(kept_state)"

  # A run that waits has done every step before the human one and no more, and
  # its recorded host refuses a rerun that names the other Mac.
  for step in $(human_steps "$host"); do
    new_case "$host-without-$step" "$host"
    do_human_steps "$host" "$step"
    before=$(paths)
    run "$host"
    is "$host-waits-at-$step" "75 $step" "$status $(last_step)"
    is "$host-waits-at-$step-after-the-steps-before-it" "$(expected_log "$host" | log_through "$step")" "$(cat "$log")"
    is "$host-waits-at-$step-with-the-host-recorded" "$host" "$(recorded)"
    is "$host-waits-at-$step-gaining-only-allowlisted-entries" '' "$(gained "$before")"
    if [[ $host != work-mac ]]; then
      is "$host-waits-at-$step-without-a-work-profile" absent "$(work_profile_state)"
    fi
    case $host in
    personal-mac) expect_refused "$host-waits-at-$step-then-refuses-work-mac" work-mac ;;
    work-mac) expect_refused "$host-waits-at-$step-then-refuses-personal-mac" personal-mac ;;
    esac
    do_human_step "$host" "$step"
    run "$host"
    is "$host-resumes-after-$step" "0 $(expected_log "$host")" "$status $(cat "$log")"
  done
done

echo "summary: $checks checks, $failures failed"
((failures == 0))
