#!/usr/bin/env bash
# Break one condition of the guard hooks at a time and require the checks in
# tests/hooks.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. Every check has a mutant here except the two that guard this
# harness (empty-path-dir-is-empty, empty-path-resolves-nothing) and the
# per-pattern checks whose pattern is not mutated: one removed pattern per
# guard stands for the table.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
# The physical path: a `path:` flakeref refuses a directory reached through a
# symlink, and macOS puts mktemp's directory under /var, a link to /private/var.
work_dir=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$work_dir"' EXIT

failures=0

expect_pass() {
  local out
  if out=$("$repo_dir/tests/hooks.sh" 2>&1); then
    echo "pass: the guards as committed"
  else
    echo "FAIL: the guards as committed should pass"
    grep -E '^(ERROR|FAIL)' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

expect_caught() { # <check>... <description> <file> <old> <new>
  local checks=$1 description=$2 file=$3 old=$4 new=$5 dir out check missing
  dir=$(mktemp -d "$work_dir/mutant.XXXX")
  mkdir -p "$dir/nix" "$dir/home/.claude"
  command cp "$repo_dir/flake.nix" "$repo_dir/flake.lock" "$dir/"
  command cp "$repo_dir/nix/agents.nix" "$dir/nix/"
  command cp -R "$repo_dir/hosts" "$dir/hosts"
  command cp -R "$repo_dir/home/.claude/hooks" "$dir/home/.claude/hooks"
  OLD=$old NEW=$new python3 - "$dir/$file" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
  out=$("$repo_dir/tests/hooks.sh" "$dir" 2>&1) || true
  missing=
  for check in $checks; do
    grep -q "^FAIL: $check:" <<<"$out" || missing="$missing $check"
  done
  if [[ -z $missing ]]; then
    echo "caught: $description"
  else
    echo "MISSED: $description (expected to fail:$missing)"
    grep -E '^(ERROR|FAIL|summary)' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

guard=home/.claude/hooks/lib/guard.sh
db=home/.claude/hooks/block-destructive-db.sh
sensitive=home/.claude/hooks/block-sensitive-read.sh

expect_pass

# The pattern tables.
expect_caught db-deny-sql-wipe-uppercase 'the raw-SQL wipe pattern is gone' \
  "$db" $'  \'truncate([[:space:]]+table)?([^[:alnum:]_]|$)\'\n' ''

expect_caught 'db-deny-sql-drop-db db-deny-quote-split db-deny-multiline' \
  'the pattern for dropping a whole database is gone' \
  "$db" $'  \'drop[[:space:]]+(database|schema)([^[:alnum:]_]|$)\'\n' ''

expect_caught sensitive-deny-remote-login-dir 'the SSH directory pattern is gone' \
  "$sensitive" $'  "${hook_home}[.]ssh${hook_end}"\n' ''

expect_caught sensitive-deny-dotenv 'the .env pattern is gone' \
  "$sensitive" $'  "(^|[^[:alnum:]_.-])[.]env${hook_end}"\n' ''

expect_caught sensitive-pass-dotenv-template \
  'the .env variants are matched by a wildcard, so the committed templates are denied too' \
  "$sensitive" '[.]env[.](local|development|dev|staging|stg|production|prod|test)' \
  '[.]env[.][[:alnum:]_-]+'

expect_caught 'sensitive-pass-repo-copy sensitive-pass-repo-vault-config' \
  'a credential path no longer has to be rooted at the home directory' \
  "$sensitive" \
  "hook_home='(^|[^[:alnum:]_.~/-])(~/|[\$][{]?home[}]?/|/users/[^/[:space:]]+/|/home/[^/[:space:]]+/)?'" \
  "hook_home='(^|[^[:alnum:]_-])'"

# The shared engine.
expect_caught db-matcher-error-denies 'a matcher that errors reads as "no match"' \
  "$guard" $'    *)\n      printf \'error %s grep-exit-%s\' "$pattern" "$rc"\n      return 0\n      ;;\n' \
  $'    *) ;;\n'

expect_caught db-internal-error-denies 'errexit is not inherited by the classification' \
  "$guard" $'shopt -s inherit_errexit\n' ''

expect_caught db-internal-error-denies 'nothing denies when the guard aborts' \
  "$guard" $'trap \'guard_on_exit\' EXIT\n' ''

expect_caught 'no-allow-decision db-deny-prisma-reset' 'the guard prints allow instead of deny' \
  "$guard" 'permissionDecision: "deny",' 'permissionDecision: "allow",'

expect_caught 'db-malformed-no-command db-malformed-null-command sensitive-malformed-no-command' \
  'input without a command string reads as an empty command instead of denying' \
  "$guard" \
  $'\'if (.tool_input.command | type) == "string" then .tool_input.command else error("no Bash command") end\'' \
  $'\'.tool_input.command // ""\''

expect_caught db-deny-quote-split 'quote concatenation is no longer removed before matching' \
  "$guard" $'  text=${text//\\"/}\n' ''

expect_caught 'db-deny-sql-wipe-uppercase db-deny-sql-drop-db' \
  'the command is matched without lowercasing it' \
  "$guard" $'  printf \'%s\' "$text" | tr \'[:upper:]\' \'[:lower:]\'\n' \
  $'  printf \'%s\' "$text"\n'

expect_caught db-deny-multiline 'newlines are left in place, so grep matches one line at a time' \
  "$guard" $'  text=${text//$\'\\n\'/ }\n' ''

# The build.
expect_caught 'db-pass-list-files sensitive-pass-read-readme' \
  "jq is resolved from the caller's PATH instead of the store" \
  nix/agents.nix \
  $'      runtimeInputs = [\n        pkgs.jq\n        pkgs.coreutils\n        pkgs.gnugrep\n      ];\n      inheritPath = false;\n' \
  $'      runtimeInputs = [\n        pkgs.coreutils\n        pkgs.gnugrep\n      ];\n      inheritPath = true;\n'

if ((failures > 0)); then
  echo "$failures mutation check(s) failed"
  exit 1
fi
echo "every mutant is caught"
