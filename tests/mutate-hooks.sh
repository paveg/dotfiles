#!/usr/bin/env bash
# Break one condition of the guard hooks at a time and require the checks in
# tests/hooks.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. A check name that ends mid-word stands for every check that
# starts with it. Every rule in a guard's table is covered by the generic
# checks of tests/hooks.sh (fires, alone, tier); the mutants here break a
# sample of them one by one, which shows those checks go red, together with
# the engine, the normalization, the tier boundary and the build. Mutants run
# in batches of MUTATE_JOBS (default 6), each in its own tree.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
# The physical path: a `path:` flakeref refuses a directory reached through a
# symlink, and macOS puts mktemp's directory under /var, a link to /private/var.
work_dir=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$work_dir"' EXIT

jobs_per_batch=${MUTATE_JOBS:-6}
mutants=0

expect_pass() {
  local out
  if out=$("$repo_dir/tests/hooks.sh" 2>&1); then
    echo "pass: the guards as committed ($(grep '^summary:' <<<"$out" | cut -d'(' -f1))"
  else
    echo "FAIL: the guards as committed should pass"
    grep -E '^(ERROR|FAIL)' <<<"$out" | head -5
    return 1
  fi
}

prepare_mutant() { # <n> <description> <file> <old> <new>; prints the mutated tree
  local n=$1 description=$2 file=$3 old=$4 new=$5 dir
  dir=$(mktemp -d "$work_dir/mutant.XXXX")
  mkdir -p "$dir/nix" "$dir/home/.claude"
  command cp "$repo_dir/flake.nix" "$repo_dir/flake.lock" "$dir/"
  command cp "$repo_dir/nix/agents.nix" "$dir/nix/"
  command cp -R "$repo_dir/hosts" "$dir/hosts"
  command cp -R "$repo_dir/home/.claude/hooks" "$dir/home/.claude/hooks"
  if ! OLD=$old NEW=$new python3 - "$dir/$file" <<'PY' 2>"$work_dir/result.$n.err"; then
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
    printf 'MISSED: %s (the mutation did not apply: %s)\n' "$description" "$(cat "$work_dir/result.$n.err")" >"$work_dir/result.$n"
    return 1
  fi
  echo "$dir"
}

grade_mutant() { # <n> <checks> <description> <tree>
  local n=$1 checks=$2 description=$3 dir=$4 out check missing=
  out=$("$repo_dir/tests/hooks.sh" "$dir" 2>&1) || true
  for check in $checks; do
    grep -q "^FAIL: $check" <<<"$out" || missing="$missing $check"
  done
  if [[ -z $missing ]]; then
    echo "caught: $description" >"$work_dir/result.$n"
  else
    {
      echo "MISSED: $description (expected to fail:$missing)"
      grep -E '^(ERROR|FAIL|summary)' <<<"$out" | head -5
    } >"$work_dir/result.$n"
  fi
}

expect_caught() { # <check>... <description> <file> <old> <new>
  local checks=$1 description=$2 file=$3 old=$4 new=$5 tree
  mutants=$((mutants + 1))
  tree=$(prepare_mutant "$mutants" "$description" "$file" "$old" "$new") || return 0
  grade_mutant "$mutants" "$checks" "$description" "$tree" &
  if ((mutants % jobs_per_batch == 0)); then
    wait
  fi
}

guard=home/.claude/hooks/lib/guard.sh
db=home/.claude/hooks/block-destructive-db.sh
sensitive=home/.claude/hooks/block-sensitive-read.sh

expect_pass

# The database table: a rule gone, a noun or an alternative gone, a comment no
# longer a gap, a construct or a client gone.
expect_caught db-fixtures-name-known-rules 'the TRUNCATE rule is gone' \
  "$db" $'guard_rule truncate deny "truncate${name_end}"\n' ''

expect_caught db-rule-drop-table-fires 'the table noun of the DROP rule matches nothing' \
  "$db" 'guard_rule drop-table deny "drop${gap}table${name_end}"' \
  'guard_rule drop-table deny "drop${gap}nosuchnoun${name_end}"'

expect_caught 'db-rule-drop-database-fires-3 db-rule-drop-database-fires-4' \
  'only whitespace may stand between two SQL keywords, not a comment' \
  "$db" "gap='([[:space:]]|/\\*[^*]*\\*/|--[^[:space:]]*[[:space:]])+'" "gap='[[:space:]]+'"

expect_caught db-rule-script-db-wipe-fires-3 'one of the wipe scripts is not listed' \
  "$db" 'db:(reset|drop|nuke|wipe|clear)' 'db:(reset|drop|nuke|clear)'

expect_caught db-rule-django-flush-fires-1 'one of the django commands is not listed' \
  "$db" '(flush|reset_db)' '(flush)'

expect_caught db-rule-client-construct-fires-2 'one database client is not listed' \
  "$db" "client='(psql|mysql|mariadb|" "client='(psql|mysql|"

expect_caught db-rule-client-construct-fires-8 'a # comment is no longer a construct' \
  "$db" "client_construct='([\$\`*?[{#]|--)'" "client_construct='([\$\`*?[{]|--)'"

expect_caught db-rule-client-construct-fires-6 'a -- option is no longer a construct' \
  "$db" "client_construct='([\$\`*?[{#]|--)'" "client_construct='([\$\`*?[{#])'"

expect_caught 'db-fixtures-name-known-rules sensitive-fixtures-name-known-rules' \
  'the reversed order of a pair of shape rules is not registered' \
  "$guard" $'  guard_rule "$1-reversed" "$2" "$4.*$3"\n' ''

expect_caught db-rule-client-after-brace-fires-7 'a client straight after an opening brace is no longer noticed' \
  "$db" $'guard_rule client-after-brace ask "[{]${client}"\n' \
  $'guard_rule client-after-brace ask "[{] ${client}"\n'

expect_caught db-rule-drop-expansion-reversed-fires-0 'a verb straight after the expansion is no longer noticed' \
  "$db" '(.*[^[:alnum:]_-])?drop' '.*[^[:alnum:]_-]drop'

# The tier boundary, in the table and in the engine, in both directions.
expect_caught 'db-rule-drop-expansion-tier db-rule-drop-expansion-fires-0' \
  'a shape rule is registered as an exact rule, so it denies' \
  "$db" 'guard_rule drop-expansion ask' 'guard_rule drop-expansion deny'

expect_caught 'db-rule-dropdb-tier db-rule-dropdb-fires-0 db-deny-postgres-cli' \
  'an exact rule is registered as a shape rule, so it only asks' \
  "$db" 'guard_rule dropdb deny' 'guard_rule dropdb ask'

expect_caught 'db-ask-brace-split sensitive-ask-glob-fragment' \
  'every ask decision is printed as deny' \
  "$guard" 'guard_emit ask "$guard_subject cannot tell' 'guard_emit deny "$guard_subject cannot tell'

expect_caught 'db-deny-prisma-reset sensitive-deny-remote-login-dir' \
  'every deny decision is printed as ask' \
  "$guard" 'guard_emit deny "$guard_subject denied this command.' 'guard_emit ask "$guard_subject denied this command.'

expect_caught 'db-ask-brace-split sensitive-ask-glob-fragment' \
  'an ask carries no account of what looked unresolvable' \
  "$guard" 'What looked unresolvable: $guard_ask_why' 'Looked at: $guard_ask_why'

expect_caught db-rule-dropdb-reason-0 'a deny reason does not quote the command' \
  "$guard" $'Rule: ${verdict#deny }\nCommand: $command\n' $'Rule: ${verdict#deny }\n'

expect_caught db-rule-dropdb-reason-0 'a deny reason does not carry the override' \
  "$guard" $'$guard_advice\n\n$guard_override_advice"\n    ;;\n  *)' $'$guard_advice"\n    ;;\n  *)'

expect_caught db-rule-drop-expansion-reason-0 'an ask reason does not carry the advice' \
  "$guard" $'$guard_advice\n\nIf you are an agent' $'If you are an agent'

expect_caught db-matcher-error-quotes-command 'a matcher-failure reason does not quote the command' \
  "$guard" $'($verdict). A guard that cannot finish denies.\n\nCommand: $command\n' \
  $'($verdict). A guard that cannot finish denies.\n'

expect_caught db-unknown-tier-denies 'a rule with a tier that is neither deny nor ask is accepted and never matches' \
  "$guard" $'  *) return 1 ;;\n' ''

expect_caught 'db-deny-beats-ask sensitive-deny-beats-ask' \
  'an ask rule is tried before a deny rule, so ask wins over deny' \
  "$guard" 'for tier in deny ask; do' 'for tier in ask deny; do'

expect_caught 'db-rule-drop-expansion-alone-0 db-rule-shadow-has-fixture' \
  'a broader ask rule masks the rule under test' \
  "$db" $'guard_rule_both_orders client-construct ask' \
  $'guard_rule shadow ask "drop"\nguard_rule_both_orders client-construct ask'

expect_caught db-rule-unproven-has-fixture 'a rule with no fixture is added' \
  "$db" $'guard_rule truncate deny "truncate${name_end}"\n' \
  $'guard_rule truncate deny "truncate${name_end}"\nguard_rule unproven deny "unproven-thing"\n'

expect_caught db-rule-ids-unique 'two rules share an id' \
  "$db" $'guard_rule truncate deny "truncate${name_end}"\n' \
  $'guard_rule truncate deny "truncate${name_end}"\nguard_rule truncate deny "truncate-again"\n'

# The credential table.
expect_caught 'sensitive-fixtures-name-known-rules sensitive-deny-remote-login-dir' 'the SSH directory is not a protected name' \
  "$sensitive" $'guard_protect ssh \'[.]ssh\'\n' ''

expect_caught 'sensitive-rule-name-ssh-fires-1 sensitive-rule-name-ssh-fires-2' \
  'the SSH directory counts only when the path is rooted at the home directory' \
  "$sensitive" $'guard_protect ssh \'[.]ssh\'\n' \
  $'guard_protect ssh \'(~/|/users/[^/[:space:]]+/|/home/[^/[:space:]]+/)[.]ssh\'\n'

expect_caught 'sensitive-fixtures-name-known-rules sensitive-deny-dotenv' '.env is not a protected name' \
  "$sensitive" $'guard_protect dotenv \'[.]env\'\n' ''

expect_caught sensitive-rule-name-config-vault-fires-3 'one vault directory under .config is not listed' \
  "$sensitive" "(1password|op|keeper|ksm|ghtkn)'" "(1password|op|keeper|ghtkn)'"

expect_caught sensitive-rule-name-dot-vault-fires-1 'one vault dot-directory is not listed' \
  "$sensitive" "'[.](1password|keeper|ghtkn)'" "'[.](1password|ghtkn)'"

expect_caught 'sensitive-fixtures-name-known-rules sensitive-deny-agent-login' 'the agent login file is not protected' \
  "$sensitive" $'guard_protect claude-credentials \'[.]claude/[.]credentials[.]json\'\n' ''

expect_caught 'sensitive-pass-regex-dot-star sensitive-pass-sed-expression sensitive-pass-brace-extensions sensitive-pass-parent-glob' \
  'the dot segment needs no name character after the dot' \
  "$sensitive" 'fragment="${guard_name_start}[.][[:alnum:]_-]"' \
  'fragment="${guard_name_start}[.]"'

expect_caught sensitive-rule-fragment-expansion-fires-1 'a backtick is not an expansion' \
  "$guard" 'guard_expansion='"'"'[$`*?[{]'"'" 'guard_expansion='"'"'[$*?[{]'"'"

expect_caught sensitive-rule-fragment-expansion-fires-4 'a bracket is not an expansion' \
  "$guard" 'guard_expansion='"'"'[$`*?[{]'"'" 'guard_expansion='"'"'[$`*?{]'"'"

expect_caught sensitive-fixtures-name-known-rules 'an expansion that replaces a name outright is no longer noticed' \
  "$sensitive" $'guard_rule slash-dot-expansion ask "/[.]${guard_expansion}"\n' ''

expect_caught 'sensitive-fixtures-name-known-rules sensitive-ask-variable-glued-before-ssh' 'a variable glued before a protected name is no longer noticed' \
  "$sensitive" $'guard_rule glued-variable-name ask "[$][[:alnum:]_]+(${glued_names})"\n' ''

# A leading dot and an expansion, wherever the word stands: each character of
# the class, and each character that may stand before the dot.
expect_caught 'sensitive-rule-word-dot-expansion-fires-0:' 'a brace straight after a leading dot is not an expansion' \
  "$sensitive" $'word_dot_expansion=\'[{$`?]\'' $'word_dot_expansion=\'[$`?]\''

expect_caught 'sensitive-rule-word-dot-expansion-fires-17:' 'a dollar sign straight after a leading dot is not an expansion' \
  "$sensitive" $'word_dot_expansion=\'[{$`?]\'' $'word_dot_expansion=\'[{`?]\''

expect_caught 'sensitive-rule-word-dot-expansion-fires-18:' 'a backtick straight after a leading dot is not an expansion' \
  "$sensitive" $'word_dot_expansion=\'[{$`?]\'' $'word_dot_expansion=\'[{$?]\''

expect_caught 'sensitive-rule-word-dot-expansion-fires-19:' 'a question mark straight after a leading dot is not an expansion' \
  "$sensitive" $'word_dot_expansion=\'[{$`?]\'' $'word_dot_expansion=\'[{$`]\''

expect_caught 'sensitive-rule-word-dot-expansion-fires-20:' 'a semicolon is not a character a word starts after' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[[:space:]&|<>={,])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-fires-21:' 'an ampersand is not a character a word starts after' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[[:space:];|<>={,])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-fires-22:' 'a pipe is not a character a word starts after' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[[:space:];&<>={,])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-fires-23:' 'a less-than sign is not a character a word starts after' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[[:space:];&|>={,])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-fires-24:' 'a greater-than sign is not a character a word starts after' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[[:space:];&|<={,])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-fires-25:' 'an equals sign is not a character a word starts after' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[[:space:];&|<>{,])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-fires-26:' 'an opening brace is not a character a word starts after' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[[:space:];&|<>=,])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-fires-27:' 'a comma is not a character a word starts after' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[[:space:];&|<>={])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-fires-28:' 'only a space, not a tab, may stand before a leading dot' \
  "$sensitive" '(^|[[:space:];&|<>={,])[.]' '(^|[ ;&|<>={,])[.]'

expect_caught 'sensitive-rule-word-dot-expansion-near-miss-0 sensitive-rule-word-dot-expansion-near-miss-1' \
  'a star and a bracket after a leading dot are expansions, so a regex and a jq filter are asked about' \
  "$sensitive" $'word_dot_expansion=\'[{$`?]\'' $'word_dot_expansion=\'[{$`?*[]\''

expect_caught 'sensitive-rule-dot-paren-glob-fires-3:' \
  'a parenthesis glob in a dot-word is no longer noticed' \
  "$sensitive" $'guard_rule dot-paren-glob ask "${guard_name_start}[.][[:alnum:]_-]*[(]"' \
  $'guard_rule dot-paren-glob ask "${guard_name_start}[.][[:alnum:]_-]+[(]"'

expect_caught 'sensitive-rule-dot-paren-glob-near-miss-2:' \
  'a parenthesis anywhere in a command that names a dot-file is asked about' \
  "$sensitive" $'guard_rule dot-paren-glob ask "${guard_name_start}[.][[:alnum:]_-]*[(]"' \
  $'guard_rule dot-paren-glob ask "${guard_name_start}[.][[:alnum:]_-].*[(]"'

expect_caught 'sensitive-rule-dot-paren-glob-fires-4: sensitive-rule-dot-paren-glob-fires-5:' \
  'a dot-word after punctuation is not a dot-word' \
  "$sensitive" $'guard_rule dot-paren-glob ask "${guard_name_start}[.]' $'guard_rule dot-paren-glob ask "(^|[[:space:]])[.]'

# After a move home, `.*` and `.[` are a read of the hidden names there.
expect_caught 'sensitive-rule-home-dot-glob-fires-0:' 'a star after a leading dot is not an expansion after a move home' \
  "$sensitive" '[.][*[]"' '[.][[]"'

expect_caught 'sensitive-rule-home-dot-glob-fires-1:' 'a bracket after a leading dot is not an expansion after a move home' \
  "$sensitive" '[.][*[]"' '[.][*]"'

expect_caught 'sensitive-rule-home-dot-glob-fires-2:' 'the $HOME form of moving home is not noticed' \
  "$sensitive" "(~|[\$][{]?home[}]?)" "(~)"

expect_caught 'sensitive-rule-home-dot-glob-fires-4:' 'a trailing slash after the home directory is not noticed' \
  "$sensitive" "[}]?)/?(" "[}]?)("

expect_caught 'sensitive-rule-home-dot-glob-fires-6:' 'a pushd with no argument is not noticed' \
  "$sensitive" '(cd|pushd)[[:space:]]*([;&|]' '(cd)[[:space:]]*([;&|]'

expect_caught 'sensitive-rule-home-dot-glob-fires-9: sensitive-rule-home-dot-glob-fires-10:' 'an option between cd and the home directory is not noticed' \
  "$sensitive" "(cd|pushd)([[:space:]]+-[[:alnum:]-]*)*[[:space:]]+(~|" "(cd|pushd)[[:space:]]+(~|"

expect_caught 'sensitive-rule-home-dot-glob-fires-7:' 'a pushd to the home directory is not noticed' \
  "$sensitive" "home_cd='(cd|pushd)" "home_cd='(cd)"

expect_caught 'sensitive-rule-home-dot-glob-fires-11:' \
  'a move home ends only at a space, not at a semicolon' \
  "$sensitive" '([^[:alnum:]_/-]|$)' '([[:space:]]|$)'

expect_caught 'sensitive-rule-home-dot-glob-fires-12: sensitive-rule-home-dot-glob-fires-13:' \
  'a dot-star starts a word only after a space, not after a semicolon or an equals sign' \
  "$sensitive" '.*[[:space:];&|<>={,][.][*[]"' '.*[[:space:]][.][*[]"'

expect_caught 'sensitive-rule-home-dot-glob-near-miss-0: sensitive-rule-home-dot-glob-near-miss-1:' \
  'a dot-star is asked about whether or not a move home came before it' \
  "$sensitive" 'guard_rule home-dot-glob ask "(${home_cd}|${bare_cd}).*' 'guard_rule home-dot-glob ask "'

expect_caught 'sensitive-rule-home-dot-glob-near-miss-3: sensitive-rule-home-dot-glob-near-miss-4:' 'a move to any directory counts as a move home' \
  "$sensitive" "home_cd='(cd|pushd)([[:space:]]+-[[:alnum:]-]*)*[[:space:]]+(~|" "home_cd='(cd|pushd)([[:space:]]+-[[:alnum:]-]*)*[[:space:]]+([^[:space:]]+|~|"

expect_caught sensitive-rule-kubeconfig-expansion-reversed-fires-1 \
  'a name straight after the expansion is no longer noticed' \
  "$sensitive" '(.*[^[:alnum:]_-])?kubeconfig' '.*[^[:alnum:]_-]kubeconfig'

# The tier boundary on the credential side.
expect_caught 'sensitive-rule-glued-variable-name-tier sensitive-rule-glued-variable-name-fires-0' \
  'a shape rule is registered as an exact rule, so it denies' \
  "$sensitive" 'guard_rule glued-variable-name ask' 'guard_rule glued-variable-name deny'

expect_caught 'sensitive-rule-name-atuin-tier sensitive-rule-name-atuin-fires-0' \
  'an exact rule is registered as a shape rule, so it only asks' \
  "$sensitive" "guard_rule \"name-\$1\" deny" "guard_rule \"name-\$1\" ask"

# The exemptions.
expect_caught sensitive-pass-dotenv-template 'no token is exempt, so the committed templates are denied too' \
  "$sensitive" $'  \'.env.example\'\n  \'.env.sample\'\n  \'.env.template\'\n' ''

expect_caught sensitive-pass-dotenv-sample 'the sample template is not exempt' \
  "$sensitive" $'  \'.env.sample\'\n' ''

expect_caught 'sensitive-deny-dotenv-unlisted-suffix sensitive-deny-dotenv-custom-suffix' \
  'two more .env suffixes are exempt' \
  "$sensitive" $'  \'.env.template\'\n' $'  \'.env.template\'\n  \'.env.ci\'\n  \'.env.docker\'\n'

expect_caught 'sensitive-deny-dotenv-template-lookalike sensitive-pass-dotenv-template-arg' \
  'an exempt token may run into a longer name and still be removed' \
  "$guard" '([^[:alnum:]_.-]|$)"' '([^[:space:]]|$)"'

expect_caught sensitive-pass-dotenv-template-twice 'only the first exempt token in a command is removed' \
  "$guard" $'    while [[ $text =~ $pattern ]]; do\n      text=${text/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]}${BASH_REMATCH[2]}"}\n    done\n' \
  $'    if [[ $text =~ $pattern ]]; then\n      text=${text/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]}${BASH_REMATCH[2]}"}\n    fi\n'

# The engine.
expect_caught 'db-matcher-error-denies db-matcher-error-in-ask-rule-denies' 'a matcher that errors reads as "no match"' \
  "$guard" $'      *)\n        printf \'error %s grep-exit-%s\' "${guard_rule_ids[index]}" "$rc"\n        return 0\n        ;;\n' \
  $'      *) ;;\n'

expect_caught db-internal-error-denies 'errexit is not inherited by the classification' \
  "$guard" $'shopt -s inherit_errexit\n' ''

expect_caught db-internal-error-denies 'nothing denies when the guard aborts' \
  "$guard" $'trap \'guard_on_exit\' EXIT\n' ''

expect_caught 'no-allow-decision db-deny-prisma-reset' 'the guard prints allow instead of its decision' \
  "$guard" 'permissionDecision: $decision,' 'permissionDecision: "allow",'

expect_caught 'db-deny-prisma-reset sensitive-deny-remote-login-dir db-ask-brace-split' \
  'the decision names the wrong hook event, which Claude Code would ignore' \
  "$guard" 'hookEventName: "PreToolUse",' 'hookEventName: "PostToolUse",'

expect_caught 'db-malformed-no-command db-malformed-null-command sensitive-malformed-no-command' \
  'input without a command string reads as an empty command instead of denying' \
  "$guard" \
  $'\'if (.tool_input.command | type) == "string" then .tool_input.command else error("no Bash command") end\'' \
  $'\'.tool_input.command // ""\''

expect_caught db-deny-quote-split 'double-quote concatenation is no longer removed before matching' \
  "$guard" $'  text=${text//\\"/}\n' ''

expect_caught sensitive-deny-single-quote-split 'single-quote concatenation is no longer removed before matching' \
  "$guard" $'  text=${text//\\\'/}\n' ''

expect_caught sensitive-deny-backslash-split 'a backslash is no longer removed before matching' \
  "$guard" $'  text=${text//\\\\/}\n' ''

expect_caught 'db-deny-sql-wipe-uppercase db-deny-sql-drop-db' \
  'the command is matched without lowercasing it' \
  "$guard" $'  printf \'%s\' "$text" | tr \'[:upper:]\' \'[:lower:]\'\n' \
  $'  printf \'%s\' "$text"\n'

expect_caught db-deny-multiline-no-indent 'newlines are left in place, so grep matches one line at a time' \
  "$guard" $'  text=${text//$\'\\n\'/$3}\n' ''

# A rule that reaches past its target, and the edges of a pattern: each is
# proved by a near miss or by a fixture that sits at a punctuation edge.
expect_caught 'db-rule-truncate-near-miss-0:' 'a verb that continues into a longer word is still the verb' \
  "$db" $'guard_rule truncate deny "truncate${name_end}"\n' $'guard_rule truncate deny "truncate"\n'

expect_caught 'db-ordinary-1: db-rule-truncate-near-miss-1:' 'an unrelated command is denied beside the verb' \
  "$db" $'guard_rule truncate deny "truncate${name_end}"\n' $'guard_rule truncate deny "(truncate|git)${name_end}"\n'

expect_caught 'sensitive-rule-name-codex-auth-near-miss-0:' 'the dot in the auth file name matches any character' \
  "$sensitive" "'[.]codex/auth[.]json'" "'[.]codex/auth.json'"

expect_caught 'db-rule-script-db-wipe-fires-5: db-rule-prisma-migrate-reset-fires-2:' 'a name ends only at a space, not at a semicolon' \
  "$db" "name_end='([^[:alnum:]_]|\$)'" "name_end='([[:space:]]|\$)'"

expect_caught 'db-rule-dropdb-fires-2:' 'the wipe binary counts only after a space, not after a slash' \
  "$db" '(^|[^[:alnum:]_])dropdb' '(^|[[:space:]])dropdb'

expect_caught 'db-rule-script-db-wipe-fires-6:' 'a wipe script counts only after a space, not after a colon' \
  "$db" 'guard_rule script-db-wipe deny "db:(' 'guard_rule script-db-wipe deny "(^|[[:space:]])db:('

expect_caught 'db-rule-drop-expansion-reversed-fires-1:' 'a verb counts only straight after the expansion' \
  "$db" '"${guard_expansion}(.*[^[:alnum:]_-])?drop"' '"${guard_expansion}drop"'

expect_caught 'sensitive-rule-name-ssh-fires-6:' 'a name counts only after a space or a slash, not after a colon' \
  "$guard" "guard_name_start='(^|[^[:alnum:]_-])'" "guard_name_start='(^|[^[:alnum:]_:-])'"

expect_caught 'sensitive-rule-name-dotenv-fires-7:' 'a name ends only at a slash, a dot or a space, not at a pipe' \
  "$sensitive" "name_end='([^[:alnum:]_-]|\$)'" "name_end='([/.[:space:]]|\$)'"

expect_caught 'sensitive-rule-fragment-expansion-fires-6:' 'a name after a dot starts with a letter, not a digit' \
  "$sensitive" 'fragment="${guard_name_start}[.][[:alnum:]_-]"' 'fragment="${guard_name_start}[.][[:alpha:]]"'

expect_caught 'sensitive-rule-glued-variable-name-fires-18:' 'a variable name has letters only, no digit or underscore' \
  "$sensitive" '"[$][[:alnum:]_]+(${glued_names})"' '"[$][[:alpha:]]+(${glued_names})"'

# The engine on input that repeats what it removes.
expect_caught 'db-deny-backslash-newline: sensitive-deny-backslash-newline:' 'a backslash and its newline are not removed as a pair' \
  "$guard" $'  text=${text//\\\\$\'\\n\'/$2}\n' ''

expect_caught 'db-deny-backslash-newline: sensitive-deny-backslash-newline:' 'only the first backslash and newline pair is removed' \
  "$guard" $'  text=${text//\\\\$\'\\n\'/$2}\n' $'  text=${text/\\\\$\'\\n\'/$2}\n'

expect_caught 'db-deny-single-quoted-backslash-newline: db-deny-heredoc-backslash-newline: db-deny-comment-backslash-newline:' \
  'a backslash and its newline are never read as a space, which is what a single-quoted string or a quoted heredoc holds' \
  "$guard" $'  for reading in "${readings[@]}"; do\n' $'  for reading in 0 2; do\n'

expect_caught 'db-deny-backslash-newline: sensitive-deny-backslash-newline:' \
  'a backslash and its newline are only ever read as a space, which is not what the shell does outside quotes' \
  "$guard" $'  for reading in "${readings[@]}"; do\n' $'  for reading in 1; do\n'

expect_caught 'sensitive-rule-home-dot-glob-fires-8:' 'a newline is never read as a command separator, so a bare cd ends its line with an argument' \
  "$guard" $'  for reading in "${readings[@]}"; do\n' $'  for reading in 0 1; do\n'

expect_caught 'db-deny-single-quoted-backslash-newline:' \
  'the later reading of a command replaces the stricter one' \
  "$guard" $'    if (($(guard_rank "$verdict") > $(guard_rank "$strictest"))); then\n' $'    if true; then\n'

expect_caught 'db-deny-ask-beside-backslash-newline:' 'an ask outranks a deny when the two readings differ' \
  "$guard" $'  ask*) printf 1 ;;\n' $'  ask*) printf 5 ;;\n'

expect_caught 'sensitive-deny-double-backslash:' 'only the first backslash is removed' \
  "$guard" $'  text=${text//\\\\/}\n' $'  text=${text/\\\\/}\n'

expect_caught 'db-deny-double-newline:' 'only the first newline is flattened' \
  "$guard" $'  text=${text//$\'\\n\'/$3}\n' $'  text=${text/$\'\\n\'/$3}\n'

expect_caught 'sensitive-deny-template-slash:' 'the dot of an exempt token matches any character' \
  "$guard" '${token//./[.]}' '${token}'

expect_caught 'sensitive-deny-template-then-dot:' 'an exempt token may run into a dot and still be removed' \
  "$guard" '([^[:alnum:]_.-]|$)"' '([^[:alnum:]_-]|$)"'

expect_caught 'sensitive-deny-template-then-other-name:' 'an exempt token takes the characters around it with it' \
  "$guard" 'text=${text/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]}${BASH_REMATCH[2]}"}' 'text=${text/"${BASH_REMATCH[0]}"/}'

expect_caught 'sensitive-deny-template-then-quote:' 'the exempt tokens are removed before the quotes are' \
  "$guard" $'    scan=$(guard_normalize "$1" "${pair_becomes[reading]}" "${newline_becomes[reading]}")\n    scan=$(guard_drop_exempt_tokens "$scan")\n' \
  $'    scan=$(guard_drop_exempt_tokens "$1")\n    scan=$(guard_normalize "$scan" "${pair_becomes[reading]}" "${newline_becomes[reading]}")\n'

expect_caught 'db-rule-client-after-brace-near-miss-1:' 'a client anywhere after an opening brace counts, not only straight after it' \
  "$db" $'guard_rule client-after-brace ask "[{]${client}"\n' $'guard_rule client-after-brace ask "[{].*${client}"\n'

expect_caught 'db-rule-drop-database-fires-11:' 'a line comment between two SQL keywords holds letters only, no hyphen' \
  "$db" "--[^[:space:]]*[[:space:]])+'" "--[[:alnum:]]*[[:space:]])+'"

expect_caught 'db-rule-drop-database-fires-12:' 'a block comment between two SQL keywords holds no space' \
  "$db" '/\*[^*]*\*/' '/\*[^*[:space:]]*\*/'

expect_caught 'db-rule-knex-rollback-all-fires-1:' 'the knex command and its task are adjacent words' \
  "$db" 'knex[[:space:]].*migrate:rollback' 'knex[[:space:]]migrate:rollback'

expect_caught 'sensitive-rule-name-dotenv-fires-6:' 'one more .env suffix is exempt' \
  "$sensitive" $'  \'.env.template\'\n' $'  \'.env.template\'\n  \'.env.local\'\n'

expect_caught 'sensitive-fixtures-name-known-rules' 'a leading dot and an expansion is no longer noticed (the class variable stays in use)' \
  "$sensitive" $'guard_rule word-dot-expansion ask "(^|[[:space:];&|<>={,])[.]${word_dot_expansion}"\n' $': "$word_dot_expansion"\n'

expect_caught 'sensitive-fixtures-name-known-rules' 'a dot-star after a move home is no longer noticed (the pattern variables stay in use)' \
  "$sensitive" $'guard_rule home-dot-glob ask "(${home_cd}|${bare_cd}).*[[:space:];&|<>={,][.][*[]"\n' $': "$home_cd$bare_cd"\n'

# The checks that demand the proofs above.
expect_caught 'db-rule-unproven-has-near-miss' 'a rule with no near miss and no reason is added' \
  "$db" $'guard_rule truncate deny "truncate${name_end}"\n' \
  $'guard_rule truncate deny "truncate${name_end}"\nguard_rule unproven deny "unproven-thing"\n'

expect_caught 'db-rule-unbounded-has-boundary' 'a rule with a boundary class and no boundary fixture is added' \
  "$db" $'guard_rule truncate deny "truncate${name_end}"\n' \
  $'guard_rule truncate deny "truncate${name_end}"\nguard_rule unbounded deny "(^|[^[:alnum:]_])unbounded"\n'

# The build.
expect_caught 'db-pass-list-files sensitive-pass-read-readme' \
  "jq is resolved from the caller's PATH instead of the store" \
  nix/agents.nix \
  $'      runtimeInputs = [\n        pkgs.jq\n        pkgs.coreutils\n        pkgs.gnugrep\n      ];\n      inheritPath = false;\n' \
  $'      runtimeInputs = [\n        pkgs.coreutils\n        pkgs.gnugrep\n      ];\n      inheritPath = true;\n'

wait

failures=0
for ((n = 1; n <= mutants; n++)); do
  cat "$work_dir/result.$n"
  if grep -q '^MISSED' "$work_dir/result.$n"; then
    failures=$((failures + 1))
  fi
done

if ((failures > 0)); then
  echo "$failures of $mutants mutants were missed"
  exit 1
fi
echo "every mutant is caught ($mutants mutants)"
