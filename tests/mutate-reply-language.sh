#!/usr/bin/env bash
# Break one condition of the reply-language hook at a time; each must turn
# tests/reply-language.sh red.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
hook=$repo_dir/home/.claude/hooks/check-reply-language.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

expect_caught() { # <description> <old> <new>
  local copy=$work/hook.sh
  OLD=$2 NEW=$3 python3 - "$hook" "$copy" <<'PY'
import os, sys
text = open(sys.argv[1]).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(sys.argv[2], "w").write(text.replace(old, new))
PY
  if "$repo_dir/tests/reply-language.sh" "$copy" >/dev/null 2>&1; then
    echo "MISSED: $1"; failures=$((failures + 1))
  else
    echo "caught: $1"
  fi
}

"$repo_dir/tests/reply-language.sh" >/dev/null || { echo "FAIL: the unmutated hook fails its tests"; exit 1; }
expect_caught 'an English reply is never judged' '($j * 3) < $l' 'false'
expect_caught 'code and URLs count as English' 'def prose: gsub("(?s)```.*?```"; "") | gsub("`[^`]*`"; "") | gsub("https?://\\S+"; "");' 'def prose: .;'
expect_caught 'a second stop is blocked again' '[[ $(jq -r '"'"'.stop_hook_active // false'"'"' <<<"$input") == true ]] && exit 0' ''
expect_caught 'a Japanese user message is not recognised' '| prose | jp) >= 5)' '| prose | jp) >= 500)'
expect_caught 'only the user message is read, not the reply after it' '$entries[$u + 1:]' '$entries[$u:$u + 1]'
expect_caught 'a short reply is judged too' '($j + $l) >= 20' '($j + $l) >= 0'
expect_caught 'the reply is read from the transcript even when Claude Code sends it' '(if $last_reply != "" then $last_reply' '(if false then $last_reply'
((failures == 0)) && echo "every mutant is caught"
