#!/usr/bin/env bash
# Run scripts/bootstrap.sh the way `curl ... | bash -s -- <host>` does, in
# throwaway homes under `env -i`, with a PATH that starts with a stub for every
# command it calls. A human step's stub makes its check pass, and uname's stub
# picks the OS, so every host runs on any runner. Each run is detached from the
# terminal, so a human step stops instead of asking. Checks: a complete run takes
# spec/bootstrap.tla's step actions in the model's order; a missing, unknown,
# wrong-OS or unrecorded host exits 2 and changes nothing; each host runs the
# expected commands, mise install last of them after the switches, and records
# itself; a second run changes nothing; with one human step undone the run
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

# A stub that appends "<cwd, with HOME as ~> <name> <args>" to the case's calls
# log, then runs the body on stdin. It finds the case directory from its own
# path, so it needs nothing from the environment `env -i` clears.
stub() { # <name> <body
  {
    echo '#!/bin/sh'
    echo 'case_dir=${0%/*}/..'
    echo "echo \"~\${PWD#\"\$HOME\"} $1 \$*\" >>\"\$case_dir/calls\""
    cat
  } >"$stubs/$1"
  chmod +x "$stubs/$1"
}

# A fresh case: a throwaway HOME, a stub for every command the script calls,
# and no human step done. A human step's command is stubbed even then, failing
# as it does before the person acts: the script puts the switched profile on
# PATH, and on a bootstrapped Mac that holds the real ghtkn. The home-manager
# switch puts decoys in ~/.nix-profile/bin, so a stub left behind that
# directory on PATH is seen.
new_case() { # <name> <host>
  local os=Darwin name
  [[ $2 != wsl ]] || os=Linux
  case_dir=$work_dir/$1
  home=$case_dir/home stubs=$case_dir/stubs calls=$case_dir/calls
  mkdir -p "$home" "$stubs" "$case_dir/decoys/bin"
  printf '#!/bin/sh\necho %s\n' "$os" >"$stubs/uname"
  chmod +x "$stubs/uname"
  stub nix <<'SH'
case $1 in
shell)
  while [ "$1" != -c ]; do shift; done
  shift
  exec "$@"
  ;;
eval) echo ryota ;;
run) [ "$2" != home-manager ] || { mkdir -p "$HOME/.nix-profile" && cp -R "$case_dir/decoys/bin" "$HOME/.nix-profile/"; } ;;
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
    printf '#!/bin/sh\necho "decoy %s $*" >>"%s"\nexit 1\n' "$name" "$calls" >"$case_dir/decoys/bin/$name"
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
# calls log first.
run() { # <arg>...
  local launcher='if (my $pid = fork) { waitpid $pid, 0; exit($? & 127 ? 128 + ($? & 127) : $? >> 8) }
    POSIX::setsid(); exec @ARGV or die "exec: $!\n"'
  : >"$calls"
  status=0
  out=$(cd "$home" && cat "$script" | env -i HOME="$home" PATH="$stubs:$base_path" DOTFILES_TEST_STUB_DIR="$stubs" \
    /usr/bin/perl -MPOSIX -e "$launcher" /bin/bash -s -- "$@" 2>&1) || status=$?
}

steps_run() { sed -n 's/^bootstrap: step [0-9]*: //p' <<<"$out"; }

# Each path below HOME with its type and mode, and a regular file's checksum.
snapshot() {
  (cd "$home" && find . | LC_ALL=C sort | while IFS= read -r path; do
    sum=
    [[ ! -f $path || -L $path ]] || sum=$(cksum <"$path")
    # shellcheck disable=SC2012 # the mode string, which BSD and GNU stat print differently
    echo "$(ls -ld "$path" | cut -c1-10) $path $sum"
  done)
}

paths() { (cd "$home" && find . | LC_ALL=C sort); }

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

expected_calls() { # <host>
  local co='~/repos/github.com/paveg/dotfiles' switch
  if [[ $1 == wsl ]]; then
    switch="$co nix eval --raw --file hosts/wsl.nix user
$co nix run home-manager -- switch --flake .#ryota@wsl"
  else
    switch="$co sudo nix run nix-darwin -- switch --flake .#$1
$co nix run nix-darwin -- switch --flake .#$1"
  fi
  echo '~ nix shell nixpkgs#git nixpkgs#ghq -c ghq get https://github.com/paveg/dotfiles'
  echo '~ ghq get https://github.com/paveg/dotfiles'
  echo "$switch"
  [[ $1 != wsl ]] || echo "$co ssh-add.exe -l"
  echo "$switch"
  echo "$co mise install"
  echo "$co ghtkn exec -- true"
  echo "$co lefthook install"
}

# Exit 2 with no command run and nothing below HOME changed.
expect_refused() { # <name> <arg>...
  local name=$1 before changed=unchanged
  shift
  before=$(snapshot)
  run "$@"
  [[ $(snapshot) == "$before" ]] || changed=changed
  is "$name" 'exit 2, calls: , home unchanged' "exit $status, calls: $(tr '\n' ';' <"$calls"), home $changed"
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
is personal-mac-stops-on-upstream-nix '75 StepInstallNix' "$status $(steps_run | tail -n 1)"

for host in personal-mac work-mac wsl; do
  new_case "$host" "$host"
  do_human_steps "$host"
  before=$(paths)
  run "$host"
  is "$host-finishes" 0 "$status"
  [[ $status == 0 ]] || tail -n 5 <<<"$out" | sed 's/^/  /'
  is "$host-takes-the-model-steps" "$model" "$(steps_run)"
  is "$host-runs-the-expected-commands" "$(expected_calls "$host")" "$(cat "$calls")"
  is "$host-installs-runtimes-after-the-last-switch" 'switch switch mise install ' \
    "$(awk '$2 == "nix" && $3 == "run" { print "switch" } $2 == "mise" { print "mise", $3 }' "$calls" | tr '\n' ' ')"
  is "$host-records-the-host" "$host" "$(cat "$home/.config/dotfiles/host" 2>/dev/null || true)"
  is "$host-home-gains-only-allowlisted-entries" '' "$(LC_ALL=C comm -13 <(echo "$before") <(paths) |
    grep -vxE '\./\.config|\./\.config/dotfiles(/host)?|\./repos(/.*)?|\./\.nix-profile(/.*)?' | tr '\n' ' ' || true)"
  if [[ $host != work-mac ]]; then
    is "$host-never-calls-ksm" '' "$(awk '$2 == "ksm"' "$calls")"
    is "$host-has-no-work-profile" absent "$([[ -e $home/.config/dots-work ]] && echo present || echo absent)"
  fi

  after=$(snapshot)
  run "$host"
  is "$host-rerun-finishes" 0 "$status"
  is "$host-rerun-changes-nothing" "$after" "$(snapshot)"

  for step in $(human_steps "$host"); do
    new_case "$host-without-$step" "$host"
    do_human_steps "$host" "$step"
    run "$host"
    is "$host-waits-at-$step" "75 $step" "$status $(steps_run | tail -n 1)"
    do_human_step "$host" "$step"
    run "$host"
    is "$host-resumes-after-$step" "0 $(expected_calls "$host")" "$status $(cat "$calls")"
  done
done

echo "summary: $checks checks, $failures failed"
((failures == 0))
