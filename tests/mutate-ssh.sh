#!/usr/bin/env bash
# Break one condition of nix/ssh_config at a time and require the checks in
# tests/ssh.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. Moving the pve block after Host * changes nothing ssh -G
# prints while no key is set in both, so that move has no mutant.
# Env: SSH_BIN is passed through to tests/ssh.sh.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0

expect_pass() {
  local out
  if out=$("$repo_dir/tests/ssh.sh" 2>&1); then
    echo "pass: the file as committed"
  else
    echo "FAIL: the file as committed should pass"
    grep '^FAIL' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

expect_caught() { # <check>... <description> <old> <new>
  local checks=$1 description=$2 old=$3 new=$4 dir out check missing
  dir=$(mktemp -d "$work_dir/mutant.XXXX")
  cp "$repo_dir/nix/ssh_config" "$dir/ssh_config"
  OLD=$old NEW=$new python3 - "$dir/ssh_config" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
  out=$("$repo_dir/tests/ssh.sh" "$dir/ssh_config" 2>&1) || true
  missing=
  grep -q '^summary:' <<<"$out" || missing=' (no summary line)'
  for check in $checks; do
    grep -q "^FAIL: $check:" <<<"$out" || missing="$missing $check"
  done
  if [[ -z $missing ]]; then
    echo "caught: $description"
  else
    echo "MISSED: $description (expected to fail:$missing)"
    grep -E '^(FAIL|summary)' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

socket='"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'

expect_pass

expect_caught 'identity-agent-github identity-agent-any-host pve-identity-agent' \
  'ssh uses whatever agent SSH_AUTH_SOCK names' \
  "  IdentityAgent $socket"$'\n' ''

expect_caught 'identity-agent-github identity-agent-any-host pve-identity-agent' 'the socket is the Linux 1Password one' \
  "$socket" '~/.1password/agent.sock'

expect_caught 'identity-agent-github identity-agent-any-host pve-identity-agent' \
  'the path loses its quotes and splits at the space' \
  "$socket" '~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock'

expect_caught 'identity-agent-any-host pve-identity-agent' 'only GitHub goes through 1Password' \
  $'Host *\n' $'Host github.com\n'

expect_caught pve-identity-agent 'pve turns the agent off, and its value comes first' \
  '  User root' $'  User root\n  IdentityAgent none'

expect_caught 'github-hostname github-no-host-key-alias github-not-forced-root' \
  'the pve block also matches github.com' \
  'Host pve' 'Host pve github.com'

expect_caught pve-hostname 'pve resolves to another address' '192.168.10.5' '192.168.10.6'
expect_caught pve-user 'pve logs in as the local user' $'  User root\n' ''
expect_caught pve-identity-file 'pve offers ssh'"'"'s default key files' $'  IdentityFile ~/.ssh/pve_ed25519.pub\n' ''
expect_caught pve-identities-only 'pve may be offered every key the agent holds' \
  'IdentitiesOnly yes' 'IdentitiesOnly no'
expect_caught pve-forward-agent 'pve gets the 1Password agent forwarded' 'ForwardAgent no' 'ForwardAgent yes'
expect_caught pve-host-key-alias 'the host key is pinned under the address, which another machine can take' \
  $'  HostKeyAlias pve\n' ''
expect_caught pve-strict-host-key-checking 'an unknown host key is offered for acceptance' \
  'StrictHostKeyChecking yes' 'StrictHostKeyChecking ask'

if ((failures > 0)); then
  echo "$failures mutation check(s) failed"
  exit 1
fi
echo "every mutant is caught"
