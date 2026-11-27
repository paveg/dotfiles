#!/usr/bin/env bash
# Fail when a tracked path matches a `Read(...)` deny rule of
# home/.claude/settings.common.json, the file the generated settings.json is
# built from: no agent could read or maintain that file (AGENTS.md). Claude Code
# reads these rules as gitignore patterns relative to the working directory, so
# git matches them from the repository root. A rule of several segments anchors
# deeper in a session started in a subdirectory, which this check does not try.
# Case is folded on every OS: whether Claude Code folds it is not established,
# and a path that differs only in case must not pass on Linux and be denied on
# macOS.
#
# A home rule (`~/...`) reaches this checkout only through ~/repos, so one
# whose first segment is a literal other name cannot match a tracked path. Any
# rule the check cannot place against the checkout fails it instead of being
# skipped.
# Usage: tests/deny-paths.sh [repo-dir]   (default: this checkout)
set -euo pipefail

repo_dir=$(cd "${1:-$(dirname "$0")/..}" && pwd)
settings=$repo_dir/home/.claude/settings.common.json
patterns=$(mktemp)
trap 'rm -f "$patterns"' EXIT

if [[ ! -f $settings ]]; then
  echo "FAIL: $settings does not exist"
  exit 1
fi
rules=$(jq -r '.permissions.deny // [] | .[] | select(startswith("Read(") and endswith(")")) | .[5:-1]' "$settings")
if [[ -z $rules ]]; then
  echo "FAIL: no Read(...) rule in $settings"
  exit 1
fi

failures=0
rule_count=0
while IFS= read -r rule; do
  rule_count=$((rule_count + 1))
  case $rule in
    '~/'*)
      first_segment=${rule#'~/'}
      first_segment=${first_segment%%/*}
      if [[ $first_segment == repos || $first_segment == *[*?[]* ]]; then
        echo "FAIL: Read($rule) may reach this checkout under ~/repos, which this check does not evaluate"
        failures=$((failures + 1))
      fi
      ;;
    /* | ./* | '!'* | '#'*)
      echo "FAIL: Read($rule) has a form this check does not evaluate"
      failures=$((failures + 1))
      ;;
    # In a deny rule, unlike in gitignore, a single directory segment before
    # `/**` matches that directory at any depth (code.claude.com/docs/en/permissions).
    [!/]*/'**')
      if [[ $rule == */*/'**' ]]; then
        printf '%s\n' "$rule" >>"$patterns"
      else
        printf '**/%s\n' "$rule" >>"$patterns"
      fi
      ;;
    *) printf '%s\n' "$rule" >>"$patterns" ;;
  esac
done <<<"$rules"

tracked=$(git -C "$repo_dir" ls-files | wc -l | tr -d ' ')
matches=$(git -C "$repo_dir" -c core.ignorecase=true ls-files --cached --ignored --exclude-from="$patterns")
while IFS= read -r path; do
  [[ -n $path ]] || continue
  echo "FAIL: the tracked path $path matches a Read(...) deny rule in home/.claude/settings.common.json"
  failures=$((failures + 1))
done <<<"$matches"

echo "summary: $tracked tracked paths against $rule_count Read rules, $failures failed"
if ((failures > 0)); then exit 1; fi
