#!/usr/bin/env bash
# Model-check every spec, then check that each property catches the bug it is
# there for: a mutant copy of the spec must fail on that property.
# Needs `tlc` on PATH (nix shell nixpkgs#tlaplus18).
set -euo pipefail

spec_dir=$(cd "$(dirname "$0")" && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

run_tlc() { # <dir> <module>
  (cd "$1" && tlc -workers auto -metadir "$work_dir/meta-$RANDOM" "$2.tla" 2>&1) || true
}

failures=0

expect_pass() { # <module>
  local out
  out=$(run_tlc "$spec_dir" "$1")
  if grep -q 'Model checking completed. No error has been found.' <<<"$out"; then
    echo "pass: $1"
  else
    echo "FAIL: $1 should pass"; grep -E 'Error|violated' <<<"$out" | head -3
    failures=$((failures + 1))
  fi
}

expect_caught() { # <module> <property-or-message> <description> <python-replace-old> <python-replace-new>
  local module=$1 expected=$2 description=$3 old=$4 new=$5 dir out
  dir=$(mktemp -d "$work_dir/mutant.XXXX")
  cp "$spec_dir/$module.tla" "$spec_dir/$module.cfg" "$dir/"
  OLD=$old NEW=$new python3 - "$dir/$module.tla" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
  out=$(run_tlc "$dir" "$module")
  if grep -q "$expected" <<<"$out"; then
    echo "caught: $description"
  else
    echo "MISSED: $description (expected \"$expected\")"; grep -E 'Error|violated|No error' <<<"$out" | head -3
    failures=$((failures + 1))
  fi
}

expect_pass bootstrap

expect_caught bootstrap 'Action property UnpushedEditsSurvive is violated' \
  'step 7 pulls over an existing work profile' \
  'IF recorded # "work-mac" \/ workProfile # "absent"' \
  'IF recorded # "work-mac"'
expect_caught bootstrap 'Invariant PersonalHostNeverTouchesKeeper is violated' \
  'a rerun may change the recorded host' \
  '/\ (recorded = NoHost \/ recorded = arg)' \
  ''
expect_caught bootstrap 'Invariant PersonalHostNeverTouchesKeeper is violated' \
  'the host reset leaves the work profile behind' \
  "/\\ recorded' = NoHost /\\ workProfile' = \"absent\"" \
  "/\\ recorded' = NoHost /\\ UNCHANGED workProfile"
expect_caught bootstrap 'Invariant WorkMacNeverFinishesWithoutProfile is violated' \
  'step 7 moves on without a work profile' \
  'ELSE Halt /\ UNCHANGED <<careful, workProfile, ksmCalled>>' \
  'ELSE Advance /\ UNCHANGED <<careful, running, workProfile, ksmCalled>>'
expect_caught bootstrap 'Invariant BadHostChangesNothing is violated' \
  'the host check lets a wrong host through' \
  'IF ArgOk THEN Advance' \
  'IF TRUE THEN Advance'
expect_caught bootstrap 'Temporal properties were violated' \
  'no way to place the work profile when Keeper is down' \
  '/\ recorded = "work-mac" /\ workProfile = "absent" /\ ~keeperUp' \
  '/\ FALSE'

expect_pass settings_writers

expect_caught settings_writers 'Invariant GuardsInEffect is violated' \
  'settings.json is written while the guard drop-in is missing (the first design, or the reverse order)' \
  '/\ managedGuard            \* the drop-in is written first' \
  ''
expect_caught settings_writers 'Action property OnlyClaudeCodeDropsOrca is violated' \
  "the generator carries Orca's entries over from the file it read" \
  "/\\ file' = {\"guard\", \"orca\"}" \
  "/\\ file' = {\"guard\"} \\cup (genBuf \\cap {\"orca\"})"

if ((failures > 0)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all specs pass, and every mutant is caught"
