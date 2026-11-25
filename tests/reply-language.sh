#!/usr/bin/env bash
# Check home/.claude/hooks/check-reply-language.sh against transcript fixtures.
# Usage: tests/reply-language.sh [hook]   (a mutant copy of the hook may be given)
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
hook=${1:-$repo_dir/home/.claude/hooks/check-reply-language.sh}
fixtures=$repo_dir/tests/fixtures/reply-language
checks=0
failures=0

run_hook() { # <transcript> [stop_hook_active] [last_assistant_message]
  jq -nc --arg p "$1" --argjson active "${2:-false}" --arg last "${3-}" \
    '{transcript_path: $p, stop_hook_active: $active} + (if $last == "" then {} else {last_assistant_message: $last} end)' |
    bash "$hook"
}

expect() { # <name> <block|pass> <hook output>
  local got=pass
  if [[ -n $3 ]]; then
    got=invalid
    if jq -e '.decision == "block" and (.reason | length > 0)' >/dev/null 2>&1 <<<"$3"; then got=block; fi
  fi
  checks=$((checks + 1))
  if [[ $got == "$2" ]]; then echo "ok: $1"; else failures=$((failures + 1)); echo "FAIL: $1: want $2, got $got"; fi
}

expect ja-user-en-reply block "$(run_hook "$fixtures/ja-user-en-reply.jsonl")"
expect ja-user-tool-en-reply block "$(run_hook "$fixtures/ja-user-tool-en-reply.jsonl")"
expect ja-user-ja-reply pass "$(run_hook "$fixtures/ja-user-ja-reply.jsonl")"
expect ja-reply-with-code pass "$(run_hook "$fixtures/ja-reply-with-code.jsonl")"
expect en-user-en-reply pass "$(run_hook "$fixtures/en-user-en-reply.jsonl")"
expect ja-user-short-en-reply pass "$(run_hook "$fixtures/ja-user-short-en-reply.jsonl")"
# The transcript can lag behind the final reply; last_assistant_message decides.
english='I merged the pull request and the checks on main passed. Nothing else needs your decision right now, and the next issue can start whenever you are ready to review it.'
expect lagging-transcript-en-reply block "$(run_hook "$fixtures/ja-user-ja-reply.jsonl" false "$english")"
expect lagging-transcript-ja-reply pass "$(run_hook "$fixtures/ja-user-en-reply.jsonl" false 'PR をマージしました。main の CI も通っています。いまあなたの判断を待っているものはありません。')"
expect second-stop-after-block pass "$(run_hook "$fixtures/ja-user-en-reply.jsonl" true)"
expect missing-transcript pass "$(run_hook /nonexistent.jsonl)"
expect malformed-input pass "$(echo 'not json' | bash "$hook" 2>/dev/null || true)"

echo "summary: $checks checks, $failures failed"
((failures == 0))
