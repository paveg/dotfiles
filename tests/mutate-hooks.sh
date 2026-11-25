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

# Emptying the nouns rather than dropping the line, which would leave the gap
# unused and fail shellcheck in the build instead of the checks.
expect_caught 'db-deny-sql-drop-db db-deny-quote-split db-deny-multiline db-deny-single-table db-deny-unlisted-client-comment' \
  'the pattern for dropping a database, a schema or a table matches no noun' \
  "$db" '(database|schema|table)' '(nosuchnoun)'

expect_caught db-deny-unlisted-client-comment \
  'only whitespace may stand between two SQL keywords, not a comment' \
  "$db" "gap='([[:space:]]|/\\*[^*]*\\*/|--[^[:space:]]*[[:space:]])+'" "gap='[[:space:]]+'"

expect_caught 'sensitive-deny-remote-login-dir sensitive-deny-other-user-home sensitive-deny-relative-parent sensitive-deny-repo-copy' \
  'the SSH directory is not a protected name' \
  "$sensitive" $'  \'[.]ssh\'\n' ''

expect_caught 'sensitive-deny-other-user-home sensitive-deny-relative-parent sensitive-deny-repo-copy' \
  'the SSH directory counts only when the path is rooted at the home directory' \
  "$sensitive" $'  \'[.]ssh\'\n' \
  $'  \'(~/|/users/[^/[:space:]]+/|/home/[^/[:space:]]+/)[.]ssh\'\n'

expect_caught 'sensitive-deny-dotenv sensitive-deny-dotenv-variant sensitive-deny-dotenv-strict-prefix' \
  '.env is not a protected name' \
  "$sensitive" $'  \'[.]env\'\n' ''

expect_caught 'sensitive-pass-dotenv-template sensitive-pass-dotenv-template-word' \
  'no token is exempt, so the committed templates are denied too' \
  "$sensitive" $'  \'.env.example\'\n  \'.env.sample\'\n  \'.env.template\'\n' ''

expect_caught 'sensitive-deny-dotenv-unlisted-suffix sensitive-deny-dotenv-custom-suffix' \
  'two more .env suffixes are exempt' \
  "$sensitive" $'  \'.env.template\'\n' $'  \'.env.template\'\n  \'.env.ci\'\n  \'.env.docker\'\n'

expect_caught 'sensitive-deny-glob-fragment sensitive-deny-glob-fragment-bare sensitive-deny-variable-stem' \
  'no dot-prefixed fragment is watched' \
  "$sensitive" 'fragment="${guard_name_start}[.][[:alnum:]_-]+"' 'fragment="nosuchfragment"'

expect_caught sensitive-deny-brace-expansion \
  'an expansion that replaces the name outright is no longer denied' \
  "$sensitive" $'  "/[.]${guard_expansion}"\n' ''

expect_caught 'sensitive-pass-regex-dot-star sensitive-pass-sed-expression sensitive-pass-brace-extensions sensitive-pass-parent-glob' \
  'the dot segment needs no name character after the dot' \
  "$sensitive" '[.][[:alnum:]_-]+"' '[.][[:alnum:]_-]*"'

expect_caught db-deny-single-table 'dropping one table is no longer matched' \
  "$db" '(database|schema|table)' '(database|schema)'

# The client rule and the fragment rule.
expect_caught 'db-deny-assembled-command db-deny-spaced-line-comment' \
  'no command counts as invoking a database client' \
  "$db" "client='(psql|mysql|mariadb|sqlite3|prisma|drizzle-kit|dropdb|pg_restore|db:)'" \
  "client='(nosuchclient)'"

expect_caught db-deny-spaced-line-comment \
  'a SQL line comment beside a client is no longer a construct' \
  "$db" "client_construct='([\$\`*?[{]|--)'" "client_construct='([\$\`*?[{])'"

expect_caught sensitive-deny-cd-home-brace \
  'moving into the home directory first is no longer noticed' \
  "$sensitive" "home_cd='cd[[:space:]]+(~|[\$][{]?home[}]?)([^[:alnum:]_/-]|\$)'" \
  "home_cd='nosuchcommand'"

expect_caught sensitive-deny-variable-stem \
  'the expansion has to stand next to the dot-prefixed name again' \
  "$sensitive" $'  "${fragment}.*${guard_expansion}"\n  "${guard_expansion}.*${fragment}"\n' \
  $'  "${fragment}${guard_expansion}"\n'

# The whole-command rule.
expect_caught 'db-deny-brace-list-piped db-deny-brace-split' \
  'one verb is missing from the shared stem list' \
  "$db" $'  drop\n' ''

expect_caught sensitive-pass-direnv-file \
  'a stem denies on its own, without an expansion anywhere in the command' \
  "$guard" $'  1) return 0 ;;\n' $'  1) ;;\n'

expect_caught sensitive-deny-dotenv-template-lookalike \
  'an exempt token is removed wherever it appears, not only where it stands alone' \
  "$guard" 'pattern="(^|[^[:alnum:]_.-])${token//./[.]}([^[:alnum:]_.-]|$)"' \
  'pattern="${token//./[.]}"'

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
