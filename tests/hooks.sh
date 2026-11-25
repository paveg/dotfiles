#!/usr/bin/env bash
# Check that the guard hooks built from <repo-dir> keep the contract in
# docs/design.md "Guardrails": each denies what it is there for with a PreToolUse
# deny decision, passes everything else in silence, never prints `allow`, denies
# an input it cannot read, and denies when its own matcher fails. Every hook runs
# under `env -i PATH=<an empty directory>`, so a guard that resolved jq from the
# caller's PATH would be caught here rather than fail open on a real machine.
# Usage: tests/hooks.sh [repo-dir]   (default: this checkout)
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
src_dir=$(cd "${1:-$repo_dir}" && pwd)
manifest=$repo_dir/tests/fixtures/hooks/commands.json
malformed_dir=$repo_dir/tests/fixtures/hooks/malformed
nix_flags=(--extra-experimental-features 'nix-command flakes')

# The physical path: a `path:` flakeref refuses a directory reached through a
# symlink, and macOS puts mktemp's directory under /var, a link to /private/var.
work_dir=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$work_dir"' EXIT
empty_path=$work_dir/empty-path
mkdir -p "$empty_path"

checks=0
failures=0
all_output=

ok() { # <name>
  checks=$((checks + 1))
  echo "ok: $1"
}

fail() { # <name> <detail>
  checks=$((checks + 1))
  failures=$((failures + 1))
  echo "FAIL: $1: $2"
}

# A broken build is an error in the harness, not a caught mutant, so it exits
# with its own code instead of counting as a failed check. It reports on stderr
# because some callers run it inside $(…), which would swallow stdout.
die() { # <message>
  echo "ERROR: $1" >&2
  exit 2
}

mutate() { # <file> <old> <new>
  OLD=$2 NEW=$3 python3 - "$1" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times in {path}: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
}

# A tree with just what the guards need to build, so that a fault can be
# injected without touching the checkout. `nix build path:…` reads a plain
# directory, where a flake inside a git checkout would see tracked files only.
new_tree() { # <name>
  local dir=$work_dir/$1
  mkdir -p "$dir/nix" "$dir/home/.claude"
  command cp "$src_dir/flake.nix" "$src_dir/flake.lock" "$dir/"
  command cp "$src_dir/nix/agents.nix" "$dir/nix/"
  command cp -R "$src_dir/hosts" "$dir/hosts"
  command cp -R "$src_dir/home/.claude/hooks" "$dir/home/.claude/hooks"
  echo "$dir"
}

build_hook() { # <tree> <name>; prints the built executable
  local tree=$1 name=$2 out
  out=$(nix "${nix_flags[@]}" build --no-link --print-out-paths "path:$tree#$name" \
    2>"$work_dir/build.err") ||
    die "building $name from $tree failed: $(tail -4 "$work_dir/build.err" | tr '\n' ' ')"
  echo "$out/bin/$name"
}

hook_rc=0
hook_out=

run_hook() { # <hook> <input-file>
  hook_rc=0
  hook_out=$(env -i PATH="$empty_path" "$1" <"$2" 2>"$work_dir/hook.err") || hook_rc=$?
  all_output+=$hook_out$'\n'
}

field_of() { # <jq-path> <output>
  local rc=0 value
  value=$(jq -r "$1 // \"\"" <<<"$2" 2>/dev/null) || rc=$?
  if ((rc != 0)); then printf 'unreadable'; else printf '%s' "$value"; fi
}

expect_deny() { # <check> <hook> <input-file> [reason-substring]
  run_hook "$2" "$3"
  local decision reason
  decision=$(field_of .hookSpecificOutput.permissionDecision "$hook_out")
  reason=$(field_of .hookSpecificOutput.permissionDecisionReason "$hook_out")
  if ((hook_rc != 0)); then
    fail "$1" "exit $hook_rc, which Claude Code lets through unless onFailure blocks it"
  elif [[ $decision != deny ]]; then
    fail "$1" "decision '$decision', want 'deny' (output: $(head -c 120 <<<"$hook_out"))"
  elif [[ -z $reason ]]; then
    fail "$1" "denied with no reason the agent can act on"
  elif [[ -n ${4:-} && $reason != *"$4"* ]]; then
    fail "$1" "reason does not mention '$4': $(head -c 160 <<<"$reason")"
  else
    ok "$1"
  fi
}

expect_silent() { # <check> <hook> <input-file>
  run_hook "$2" "$3"
  if ((hook_rc != 0)); then
    fail "$1" "exit $hook_rc with output '$(head -c 120 <<<"$hook_out")'"
  elif [[ -n $hook_out ]]; then
    fail "$1" "printed '$(head -c 160 <<<"$hook_out")'"
  else
    ok "$1"
  fi
}

hook_input() { # <command>; prints the file holding one PreToolUse(Bash) input
  local file=$work_dir/input.json
  jq -n --arg command "$1" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $command}}' >"$file"
  echo "$file"
}

command -v jq >/dev/null || die "this test needs jq to read the fixtures and the hooks' output"

committed=$(new_tree committed)

# No stdin can make the pinned grep exit 2, and no stdin can make a command
# inside the classification fail, so those two paths are reached by building a
# guard with the fault injected. Both live in the shared engine, so injecting
# into one guard exercises them for both.
matcher_error=$(new_tree matcher-error)
mutate "$matcher_error/home/.claude/hooks/block-destructive-db.sh" \
  $'guard_patterns=(\n' $'guard_patterns=(\n  \'a[\'\n'
internal_error=$(new_tree internal-error)
mutate "$internal_error/home/.claude/hooks/lib/guard.sh" \
  $'  local scan=$1 pattern rc\n' $'  local scan=$1 pattern rc\n  false\n'

hook_db=$(build_hook "$committed" block-destructive-db)
hook_sensitive=$(build_hook "$committed" block-sensitive-read)
hook_db_matcher_error=$(build_hook "$matcher_error" block-destructive-db)
hook_db_internal_error=$(build_hook "$internal_error" block-destructive-db)

hook_for() { # <guard key>
  case $1 in
  db) echo "$hook_db" ;;
  sensitive) echo "$hook_sensitive" ;;
  *) die "unknown guard key '$1' in $manifest" ;;
  esac
}

stray=$(find "$empty_path" -mindepth 1 | tr '\n' ' ')
if [[ -z $stray ]]; then
  ok empty-path-dir-is-empty
else
  fail empty-path-dir-is-empty "$empty_path holds$stray"
fi

if env -i PATH="$empty_path" /usr/bin/env jq --version >/dev/null 2>&1; then
  fail empty-path-resolves-nothing "jq still resolved under PATH=$empty_path"
else
  ok empty-path-resolves-nothing
fi

while IFS=$'\t' read -r guard expect name; do
  input=$(hook_input "$(jq -r --arg g "$guard" --arg e "$expect" --arg n "$name" \
    '.[$g][$e][$n]' "$manifest")")
  case $expect in
  deny) expect_deny "$guard-deny-$name" "$(hook_for "$guard")" "$input" ;;
  pass) expect_silent "$guard-pass-$name" "$(hook_for "$guard")" "$input" ;;
  *) die "unknown expectation '$expect' in $manifest" ;;
  esac
done < <(jq -r 'to_entries[] | .key as $g | .value | to_entries[] | .key as $e
  | .value | keys_unsorted[] | "\($g)\t\($e)\t\(.)"' "$manifest")

for fixture in "$malformed_dir"/*.json; do
  name=$(basename "$fixture" .json)
  expect_deny "db-malformed-$name" "$hook_db" "$fixture"
  expect_deny "sensitive-malformed-$name" "$hook_sensitive" "$fixture"
done

harmless=$(hook_input 'ls -la')
expect_deny db-matcher-error-denies "$hook_db_matcher_error" "$harmless" grep-exit-2
expect_deny db-internal-error-denies "$hook_db_internal_error" "$harmless" "internal error"

if grep -qE '"permissionDecision": ?"allow"' <<<"$all_output"; then
  fail no-allow-decision "a guard printed an allow decision, which skips the permission prompt"
else
  ok no-allow-decision
fi

echo "summary: $checks checks, $failures failed (guards built from $src_dir)"
if ((failures > 0)); then exit 1; fi
