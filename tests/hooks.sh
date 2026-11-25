#!/usr/bin/env bash
# Check that the guard hooks built from <repo-dir> keep the contract in
# docs/design.md "Guardrails": each denies its exact rules with a PreToolUse
# deny decision, asks about its shape rules with an ask decision, passes
# everything else in silence, never prints `allow`, denies an input it cannot
# read, and denies when its own matcher fails. Every hook runs under
# `env -i PATH=<an empty directory>`, so a guard that resolved jq from the
# caller's PATH would be caught here rather than fail open on a real machine.
#
# Every rule in a guard's table has to prove itself alone: its fixtures get the
# rule's decision from the built guard (naming the rule in the reason), and
# with the rule removed and every other rule kept, the decision changes. The
# second half is what exposes a rule that another rule masks. It runs the
# unbuilt engine and table under the interpreter and PATH of the built guard,
# so the production build carries no switch for it.
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

expect_decision() { # <check> <hook> <input-file> <deny|ask> [reason-substring]
  run_hook "$2" "$3"
  local decision event reason
  decision=$(field_of .hookSpecificOutput.permissionDecision "$hook_out")
  event=$(field_of .hookSpecificOutput.hookEventName "$hook_out")
  reason=$(field_of .hookSpecificOutput.permissionDecisionReason "$hook_out")
  if ((hook_rc != 0)); then
    fail "$1" "exit $hook_rc, which Claude Code lets through unless onFailure blocks it"
  elif [[ $decision != "$4" ]]; then
    fail "$1" "decision '$decision', want '$4' (output: $(head -c 120 <<<"$hook_out"))"
  elif [[ $event != PreToolUse ]]; then
    fail "$1" "hookEventName '$event', want 'PreToolUse', so Claude Code would ignore the decision"
  elif [[ -z $reason ]]; then
    fail "$1" "$4 with no reason the agent or the human can act on"
  elif [[ -n ${5:-} && $reason != *"$5"* ]]; then
    fail "$1" "reason does not mention '$5': $(head -c 160 <<<"$reason")"
  else
    ok "$1"
  fi
}

expect_deny() { # <check> <hook> <input-file> [reason-substring]
  expect_decision "$1" "$2" "$3" deny "${4:-}"
}

expect_ask() { # <check> <hook> <input-file> [reason-substring]
  expect_decision "$1" "$2" "$3" ask "${4:-}"
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
# inside the classification fail, so those paths are reached by building a
# guard with the fault injected. All live in the shared engine, so injecting
# into one guard exercises them for both.
matcher_error_deny=$(new_tree matcher-error-deny)
mutate "$matcher_error_deny/home/.claude/hooks/block-destructive-db.sh" \
  $'guard_rule truncate deny "truncate${name_end}"\n' \
  $'guard_rule truncate deny "truncate${name_end}"\nguard_rule broken deny \'a[\'\n'
matcher_error_ask=$(new_tree matcher-error-ask)
mutate "$matcher_error_ask/home/.claude/hooks/block-destructive-db.sh" \
  $'guard_rule drop-expansion ask' \
  $'guard_rule broken ask \'a[\'\nguard_rule drop-expansion ask'
internal_error=$(new_tree internal-error)
mutate "$internal_error/home/.claude/hooks/lib/guard.sh" \
  $'  local scan=$1 tier index rc\n' $'  local scan=$1 tier index rc\n  false\n'

hook_db=$(build_hook "$committed" block-destructive-db)
hook_sensitive=$(build_hook "$committed" block-sensitive-read)
hook_db_matcher_error_deny=$(build_hook "$matcher_error_deny" block-destructive-db)
hook_db_matcher_error_ask=$(build_hook "$matcher_error_ask" block-destructive-db)
hook_db_internal_error=$(build_hook "$internal_error" block-destructive-db)

hook_for() { # <guard key>
  case $1 in
  db) echo "$hook_db" ;;
  sensitive) echo "$hook_sensitive" ;;
  *) die "unknown guard key '$1' in $manifest" ;;
  esac
}

guard_file_for() { # <guard key>; prints the unbuilt guard's table
  case $1 in
  db) echo "$committed/home/.claude/hooks/block-destructive-db.sh" ;;
  sensitive) echo "$committed/home/.claude/hooks/block-sensitive-read.sh" ;;
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
  ask) expect_ask "$guard-ask-$name" "$(hook_for "$guard")" "$input" ;;
  pass) expect_silent "$guard-pass-$name" "$(hook_for "$guard")" "$input" ;;
  *) die "unknown expectation '$expect' in $manifest" ;;
  esac
done < <(jq -r 'del(.ordinary) | to_entries[] | .key as $g | .value | to_entries[]
  | select(.key != "rules") | .key as $e
  | .value | keys_unsorted[] | "\($g)\t\($e)\t\(.)"' "$manifest")

for fixture in "$malformed_dir"/*.json; do
  name=$(basename "$fixture" .json)
  expect_deny "db-malformed-$name" "$hook_db" "$fixture"
  expect_deny "sensitive-malformed-$name" "$hook_sensitive" "$fixture"
done

# The rule tables. The harness is the unbuilt engine and table, run by the
# built guard's own bash with its own pinned PATH, so grep and jq are the ones
# the guard ships with.
harness_bash=$(head -1 "$hook_db")
harness_bash=${harness_bash#'#!'}
harness_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$hook_db")
if [[ ! -x $harness_bash || -z $harness_path ]]; then
  die "cannot read the interpreter and PATH out of $hook_db"
fi

cat >"$work_dir/harness.sh" <<'HARNESS'
set -o errexit -o nounset -o pipefail
engine=$1
guard_file=$2
mode=$3
# shellcheck source=/dev/null
source "$engine"
# shellcheck source=/dev/null
source "$guard_file"
guard_finished=1

without_rule() { # <id>
  local ids=() tiers=() regexes=() index
  for index in "${!guard_rule_ids[@]}"; do
    if [[ ${guard_rule_ids[index]} != "$1" ]]; then
      ids+=("${guard_rule_ids[index]}")
      tiers+=("${guard_rule_tiers[index]}")
      regexes+=("${guard_rule_regexes[index]}")
    fi
  done
  guard_rule_ids=("${ids[@]}")
  guard_rule_tiers=("${tiers[@]}")
  guard_rule_regexes=("${regexes[@]}")
}

case $mode in
list)
  for index in "${!guard_rule_ids[@]}"; do
    printf '%s\t%s\n' "${guard_rule_ids[index]}" "${guard_rule_tiers[index]}"
  done
  ;;
without) # <manifest> <guard key>
  manifest=$4
  key=$5
  for id in "${guard_rule_ids[@]}"; do
    count=$(jq -r --arg g "$key" --arg id "$id" '(.[$g].rules[$id] // []) | length' "$manifest")
    for ((n = 0; n < count; n++)); do
      fixture=$(jq -j --arg g "$key" --arg id "$id" --argjson n "$n" '.[$g].rules[$id][$n]' "$manifest")
      verdict=$(
        without_rule "$id"
        guard_decide "$fixture"
      )
      printf '%s\t%s\t%s\n' "$id" "$n" "${verdict:-none}"
    done
  done
  ;;
esac
HARNESS

run_harness() { # <guard key> <mode> [args...]
  local key=$1
  shift
  env -i PATH="$harness_path" "$harness_bash" "$work_dir/harness.sh" \
    "$committed/home/.claude/hooks/lib/guard.sh" "$(guard_file_for "$key")" "$@"
}

for guard in db sensitive; do
  hook=$(hook_for "$guard")
  rules=$work_dir/$guard-rules.tsv
  verdicts=$work_dir/$guard-verdicts.tsv
  run_harness "$guard" list >"$rules" || die "listing the $guard rules failed"
  run_harness "$guard" without "$manifest" "$guard" >"$verdicts" ||
    die "deciding the $guard fixtures without their rules failed"

  duplicates=$(cut -f1 "$rules" | sort | uniq -d | tr '\n' ' ')
  if [[ -z $duplicates ]]; then
    ok "$guard-rule-ids-unique"
  else
    fail "$guard-rule-ids-unique" "duplicated: $duplicates"
  fi

  unknown=$(jq -r --arg g "$guard" '.[$g].rules | keys[]' "$manifest" |
    grep -vxFf <(cut -f1 "$rules") | tr '\n' ' ' || true)
  if [[ -z $unknown ]]; then
    ok "$guard-fixtures-name-known-rules"
  else
    fail "$guard-fixtures-name-known-rules" "no such rule: $unknown"
  fi

  while IFS=$'\t' read -r id tier; do
    count=$(jq -r --arg g "$guard" --arg id "$id" '(.[$g].rules[$id] // []) | length' "$manifest")
    if ((count == 0)); then
      fail "$guard-rule-$id-has-fixture" "no fixture in $manifest; a rule nothing proves can be broken unseen"
      continue
    fi
    for ((n = 0; n < count; n++)); do
      input=$(hook_input "$(jq -j --arg g "$guard" --arg id "$id" --argjson n "$n" \
        '.[$g].rules[$id][$n]' "$manifest")")
      expect_decision "$guard-rule-$id-fires-$n" "$hook" "$input" "$tier" "Rule: $id"$'\n'
      without=$(awk -F'\t' -v id="$id" -v n="$n" '$1 == id && $2 == n { print $3 }' "$verdicts")
      if [[ ${without%% *} != "$tier" ]]; then
        ok "$guard-rule-$id-alone-$n"
      else
        fail "$guard-rule-$id-alone-$n" "still a $tier without the rule ($without), so another rule masks it"
      fi
    done
  done <"$rules"
done

# Commands a person types every day, to show what the shape rules cost. Not a
# check: the counts are read off this line.
for guard in db sensitive; do
  denied=0 asked=0 silent=0 total=0
  while IFS= read -r command; do
    run_hook "$(hook_for "$guard")" "$(hook_input "$command")"
    total=$((total + 1))
    case $(field_of .hookSpecificOutput.permissionDecision "$hook_out") in
    deny)
      denied=$((denied + 1))
      echo "measured: $guard denied: $command"
      ;;
    ask)
      asked=$((asked + 1))
      echo "measured: $guard asked: $command"
      ;;
    *) silent=$((silent + 1)) ;;
    esac
  done < <(jq -r '.ordinary[]' "$manifest")
  echo "measured: $guard guard on $total ordinary commands: $denied denied, $asked asked, $silent silent"
done

# A command that matches a shape rule and an exact rule is denied, not asked.
expect_deny db-deny-beats-ask "$hook_db" \
  "$(hook_input "psql -d app_dev -c 'DROP TABLE users' --echo-all")" "Rule: drop-table"
expect_deny sensitive-deny-beats-ask "$hook_sensitive" \
  "$(hook_input 'cat ~/.s* ~/.ssh/id_ed25519')" "Rule: name-ssh"

harmless=$(hook_input 'ls -la')
expect_deny db-matcher-error-denies "$hook_db_matcher_error_deny" "$harmless" grep-exit-2
expect_deny db-matcher-error-in-ask-rule-denies "$hook_db_matcher_error_ask" "$harmless" grep-exit-2
expect_deny db-internal-error-denies "$hook_db_internal_error" "$harmless" "internal error"

if grep -qE '"permissionDecision": ?"allow"' <<<"$all_output"; then
  fail no-allow-decision "a guard printed an allow decision, which skips the permission prompt"
else
  ok no-allow-decision
fi

echo "summary: $checks checks, $failures failed (guards built from $src_dir)"
if ((failures > 0)); then exit 1; fi
