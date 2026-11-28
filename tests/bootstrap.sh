#!/usr/bin/env bash
# Run scripts/bootstrap.sh the way `curl ... | bash -s -- <host>` does, in
# throwaway homes under `env -i`, with a PATH that starts with a stub for every
# command it calls. A human step's stub makes its check pass, and uname's stub
# picks the OS, so every host runs on any runner. Each run is detached from the
# terminal, so a human step stops instead of asking. A trace sourced through
# BASH_ENV logs each Step* function the script enters, in order with the stubs'
# calls. Checks: a complete run enters spec/bootstrap.tla's step actions in the
# model's order and no other Step* function; a missing, unknown,
# wrong-OS or unrecorded host exits 2 and changes nothing; each host runs the
# expected commands, mise install last of them after the switches, and records
# itself; neither that run nor a second one changes an existing checkout or the
# hand-placed work profile, and the second changes nothing below $HOME, link
# targets included; with one human step undone the run
# exits 75 at that step and finishes once the step is done; personal hosts
# never call ksm or create ~/.config/dots-work/; $HOME gains only the recorded
# host and what the stubbed clone and switch create.
# Usage: tests/bootstrap.sh [script [spec]]   (mutant copies may be given)
# SC2016: the stub lines and the perl launcher are source for another shell or
#         for perl, expanded when they run. SC2088: the ~ in the expected calls
#         is the log's notation for HOME.
# shellcheck disable=SC2016,SC2088
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
script=${1:-$repo_dir/scripts/bootstrap.sh}
spec=${2:-$repo_dir/spec/bootstrap.tla}
base_path=/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin
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
# then runs the body on stdin. It finds the case directory from its own path,
# so it needs nothing from the environment `env -i` clears.
stub() { # <name> <body
  {
    echo '#!/bin/sh'
    echo 'case_dir=${0%/*}/..'
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
  mkdir -p "$home" "$stubs" "$case_dir/decoys/bin"
  trace >"$case_dir/trace.bash"
  printf '#!/bin/sh\necho %s\n' "$os" >"$stubs/uname"
  chmod +x "$stubs/uname"
  stub nix <<'SH'
case $1 in
shell)
  mkdir -p "$HOME/.cache/nix"
  while [ "$1" != -c ]; do shift; done
  shift
  exec "$@"
  ;;
eval) echo ryota ;;
run)
  if [ "$2" = home-manager ]; then
    mkdir -p "$HOME/.local/state/nix/profiles"
    ln -sfn "$case_dir/decoys" "$HOME/.local/state/nix/profiles/profile"
    ln -sfn "$HOME/.local/state/nix/profiles/profile" "$HOME/.nix-profile"
  fi
  ;;
esac
SH
  stub sudo <<'SH'
command=$1
shift
exec "${0%/*}/$command" "$@"
SH
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
  for name in determinate-nixd mise lefthook ksm; do stub "$name" </dev/null; done
  for name in mise ghtkn lefthook; do
    printf '#!/bin/sh\necho "decoy %s $*" >>"%s"\nexit 1\n' "$name" "$log" >"$case_dir/decoys/bin/$name"
    chmod +x "$case_dir/decoys/bin/$name"
  done
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
# session with no controlling terminal. Sets status and out, and empties the
# log first.
run() { # <arg>...
  local launcher='if (my $pid = fork) { waitpid $pid, 0; exit($? & 127 ? 128 + ($? & 127) : $? >> 8) }
    POSIX::setsid(); exec @ARGV or die "exec: $!\n"'
  : >"$log"
  status=0
  out=$(cd "$home" && cat "$script" | env -i HOME="$home" PATH="$stubs:$base_path" DOTFILES_TEST_STUB_DIR="$stubs" \
    BASH_ENV="$case_dir/trace.bash" /usr/bin/perl -MPOSIX -e "$launcher" /bin/bash -s -- "$@" 2>&1) || status=$?
}

steps_run() { sed -n 's/^step //p' "$log"; }
last_step() { steps_run | tail -n 1; }
log_lines() { tr '\n' ';' <"$log"; }

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

model=$(model_steps)

# A fresh case for each, so that what one run wrote cannot refuse the next.
new_case no-host personal-mac
expect_refused no-host-refused
new_case unknown-host personal-mac
expect_refused unknown-host-refused laptop
new_case wrong-os personal-mac
expect_refused wrong-os-refused wsl
new_case wrong-os-on-linux wsl
expect_refused wrong-os-refused-on-linux personal-mac
new_case unrecorded-host personal-mac
mkdir -p "$home/.config/dotfiles"
echo personal-mac >"$home/.config/dotfiles/host"
expect_refused unrecorded-host-refused work-mac

new_case upstream-nix personal-mac
do_human_steps personal-mac
rm "$stubs/determinate-nixd"
run personal-mac
is personal-mac-stops-on-upstream-nix '75 StepInstallNix' "$status $(last_step)"

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
  is "$host-records-the-host" "$host" "$(cat "$home/.config/dotfiles/host" 2>/dev/null || true)"
  is "$host-home-gains-only-allowlisted-entries" '' "$(gained "$before")"
  is "$host-keeps-what-was-there" "$kept_before" "$(kept_state)"
  if [[ $host != work-mac ]]; then
    is "$host-never-calls-ksm" '' "$(awk '$2 == "ksm"' "$log")"
    is "$host-has-no-work-profile" absent "$([[ -e $home/.config/dots-work ]] && echo present || echo absent)"
  fi

  after=$(snapshot)
  run "$host"
  is "$host-rerun-finishes" 0 "$status"
  is "$host-rerun-changes-nothing" "$after" "$(snapshot)"
  is "$host-rerun-keeps-what-was-there" "$kept_before" "$(kept_state)"

  for step in $(human_steps "$host"); do
    new_case "$host-without-$step" "$host"
    do_human_steps "$host" "$step"
    run "$host"
    is "$host-waits-at-$step" "75 $step" "$status $(last_step)"
    do_human_step "$host" "$step"
    run "$host"
    is "$host-resumes-after-$step" "0 $(expected_log "$host")" "$status $(cat "$log")"
  done
done

echo "summary: $checks checks, $failures failed"
((failures == 0))
