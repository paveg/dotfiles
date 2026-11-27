#!/usr/bin/env bash
# Break one condition of the reply-language hook at a time; each must turn
# tests/reply-language.sh red.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
hook=$repo_dir/home/.claude/hooks/check-reply-language.sh
# shellcheck source=tests/lib/mutate.sh
source "$repo_dir/tests/lib/mutate.sh"

run_mutant() { # <dir> <old> <new>; succeeds when the tests fail on the mutated copy
  local copy=$1/hook.sh old=$2 new=$3
  cp "$hook" "$copy"
  mutate_apply "$copy" "$old" "$new" || return
  ! "$repo_dir/tests/reply-language.sh" "$copy" >/dev/null 2>&1
}

expect_caught() { # <description> <old> <new>
  mutant "$1" run_mutant "$2" "$3"
}

mutate_baseline 'the hook as committed' "$repo_dir/tests/reply-language.sh"
expect_caught 'an English reply is never judged' '($j * 3) < $l' 'false'
expect_caught 'code and URLs count as English' 'def prose: gsub("(?s)```.*?```"; "") | gsub("`[^`]*`"; "") | gsub("https?://\\S+"; "");' 'def prose: .;'
expect_caught 'a second stop is blocked again' '[[ $(jq -r '"'"'.stop_hook_active // false'"'"' <<<"$input") == true ]] && exit 0' ''
expect_caught 'a Japanese user message is not recognised' '| prose | jp) >= 5)' '| prose | jp) >= 500)'
expect_caught 'only the user message is read, not the reply after it' '$entries[$u + 1:]' '$entries[$u:$u + 1]'
expect_caught 'a short reply is judged too' '($j + $l) >= 20' '($j + $l) >= 0'
expect_caught 'the reply is read from the transcript even when Claude Code sends it' '(if $last_reply != "" then $last_reply' '(if false then $last_reply'
mutate_finish
