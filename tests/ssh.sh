#!/usr/bin/env bash
# Check <config> (default nix/ssh_config), which nix/home.nix installs as
# ~/.ssh/config on macOS, with no Nix switch: ssh to GitHub goes through the
# 1Password agent's socket. On wsl git hands ssh to Windows instead, which
# tests/git.sh checks. OpenSSH expands ~ from the passwd entry, not $HOME, so
# a temporary HOME cannot stand in for the real one: the file is passed with
# -F, which also keeps /etc/ssh/ssh_config out, and the socket is expected
# under the passwd home. ssh -G only parses; nothing connects.
# tests/packages.sh checks that the built configuration installs the file.
# Usage: tests/ssh.sh [config]
# Env: SSH_BIN overrides the ssh to test.
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
config=${1:-$repo_dir/nix/ssh_config}
ssh_bin=${SSH_BIN:-$(command -v ssh)}
passwd_home=$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')
socket="$passwd_home/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

work_dir=$(mktemp -d)
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

resolved() { # <host> <key>
  local out
  out=$(env -i HOME="$work_dir" PATH=/usr/bin:/bin "$ssh_bin" -F "$config" -G "$1" 2>&1) ||
    { tr '\n' ' ' <<<"$out" | cut -c1-200; return; }
  sed -n "s/^$2 //p" <<<"$out"
}

is identity-agent-github "$socket" "$(resolved github.com identityagent)"
# Every host, as 1Password's docs give it, not GitHub alone.
is identity-agent-any-host "$socket" "$(resolved host.example.invalid identityagent)"

echo "summary: $checks checks, $failures failed ($("$ssh_bin" -V 2>&1), config $config)"
if ((failures > 0)); then exit 1; fi
