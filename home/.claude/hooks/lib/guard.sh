# The engine shared by the guards of docs/adr/0007-agent-guardrails.md.
# nix/agents.nix concatenates this file in front of a guard, which sets
# guard_subject, guard_ask_why and guard_advice and registers its rules with
# guard_rule, and appends the call to guard_main. A guard file only defines, so
# tests/hooks.sh can source it and decide with one rule removed.
# writeShellApplication supplies the shebang, errexit, nounset, pipefail and the
# pinned PATH, so nothing here resolves a dependency from the caller's PATH.
#
# The contract: a guard prints a PreToolUse `deny` decision when an exact rule
# matches, when it cannot read its input, and when its matcher errors; an `ask`
# decision when only a shape rule matches; and nothing at all otherwise. `deny`
# wins over `ask`. It never prints `allow`, which would skip the permission
# prompt, and exit 0 with no output is not an approval.

shopt -s inherit_errexit

guard_finished=0

# Tokens a guard treats as safe where they stand alone, such as a committed
# .env template. A guard that has none leaves this empty.
guard_exempt_tokens=()

guard_override_advice='If this is deliberate, run the command in your own shell (the guard only sees tool-invoked Bash), or add a narrow per-project rule to .claude/settings.json permissions.allow.'

# Only exit 0 with a deny decision blocks the call without `onFailure: "block"`,
# so an abort on the way to that decision has to end here. The message is a
# fixed string printed without jq, because jq may be what failed.
# SC2329: shellcheck does not follow the trap below into this handler.
# shellcheck disable=SC2329
guard_on_exit() {
  if ((guard_finished == 1)); then
    return 0
  fi
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"A dotfiles guard hook stopped with an internal error, so this tool call is denied. A guard that cannot finish cannot tell a safe command from a destructive one. Run the command in your own shell if you are sure of it, or add a narrow per-project rule to .claude/settings.json permissions.allow."}}'
  exit 0
}
trap 'guard_on_exit' EXIT

guard_emit() { # <deny|ask> <reason>
  local json
  json=$(jq -n --arg decision "$1" --arg reason "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $decision,
      permissionDecisionReason: $reason
    }
  }')
  guard_finished=1
  printf '%s\n' "$json"
  exit 0
}

guard_pass() {
  guard_finished=1
  exit 0
}

# The character before a name, so that a pattern does not match the tail of a
# longer word. A slash, a tilde, a brace or a quote's old position all qualify.
guard_name_start='(^|[^[:alnum:]_-])'

# Anything a shell expands and a matcher cannot. Quotes, backslashes and
# newlines are gone by the time a pattern runs, but one of these can still hold
# a protected name apart or build one at run time.
guard_expansion='[$`*?[{]'

# The rule table, in three parallel arrays. A `deny` rule is an exact pattern: a
# literal command or name the guard exists for. An `ask` rule is a shape
# heuristic: the command may or may not do the harm, and only a human can tell.
# Each id is unique and has a fixture in tests/fixtures/hooks/commands.json that
# the rule alone has to catch.
guard_rule_ids=()
guard_rule_tiers=()
guard_rule_regexes=()

guard_rule() { # <id> <deny|ask> <lowercase ERE>
  case $2 in
  deny | ask) ;;
  *) return 1 ;;
  esac
  guard_rule_ids+=("$1")
  guard_rule_tiers+=("$2")
  guard_rule_regexes+=("$3")
}

# Two rules for "A and B in either order, anywhere in the command", because one
# alternation would let a fixture for one order keep the other order alive.
guard_rule_both_orders() { # <id> <deny|ask> <ERE A> <ERE B>
  guard_rule "$1" "$2" "$3.*$4"
  guard_rule "$1-reversed" "$2" "$4.*$3"
}

# An exempt token leaves the scan where it stands alone between characters that
# cannot continue a name. Matching "every name but these" in one regex needs a
# negative lookahead ERE does not have, and spelling it out by hand let a
# strict prefix (.env.exam) through. Comparing whole tokens cannot. Only the
# token goes, never the word around it, which may name something else
# (`~/.ssh/id>/tmp/x.env.example`).
guard_drop_exempt_tokens() { # <normalized-command>
  local text=$1 token pattern
  for token in "${guard_exempt_tokens[@]}"; do
    pattern="(^|[^[:alnum:]_.-])${token//./[.]}([^[:alnum:]_.-]|$)"
    while [[ $text =~ $pattern ]]; do
      text=${text/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]}${BASH_REMATCH[2]}"}
    done
  done
  printf '%s' "$text"
}

# Drop quote and backslash concatenation so that token splitting cannot hide an
# operation, flatten the newlines because grep matches one line at a time, and
# lowercase. A backslash and the newline after it go first, as one pair, and
# become <joiner>. Over-normalizing can only add a pause for review; from here
# there is no path to an allow.
guard_normalize() { # <command> <what a backslash and its newline become>
  local text=$1
  text=${text//\\$'\n'/$2}
  text=${text//\"/}
  text=${text//\'/}
  text=${text//\\/}
  text=${text//$'\n'/ }
  printf '%s' "$text" | tr '[:upper:]' '[:lower:]'
}

# Prints `<tier> <id>` for the first matching rule, trying every `deny` rule
# before any `ask` rule; `error <id> grep-exit-<rc>` when the matcher itself
# fails; and nothing when no rule matches. grep returns 1 for no match and 2 or
# more for an error, and only 1 counts as no match. This runs inside $(…), where
# errexit is suspended without inherit_errexit, so an unexpected failure aborts
# instead of reading as "no match": it must not print a decision itself.
guard_classify() { # <normalized-command>
  local scan=$1 tier index rc
  for tier in deny ask; do
    for index in "${!guard_rule_ids[@]}"; do
      if [[ ${guard_rule_tiers[index]} != "$tier" ]]; then
        continue
      fi
      rc=0
      grep -qE -e "${guard_rule_regexes[index]}" <<<"$scan" 2>/dev/null || rc=$?
      case $rc in
      0)
        printf '%s %s' "$tier" "${guard_rule_ids[index]}"
        return 0
        ;;
      1) ;;
      *)
        printf 'error %s grep-exit-%s' "${guard_rule_ids[index]}" "$rc"
        return 0
        ;;
      esac
    done
  done
  return 0
}

# error before deny before ask before nothing.
guard_rank() { # <verdict>
  case $1 in
  error*) printf 3 ;;
  deny*) printf 2 ;;
  ask*) printf 1 ;;
  *) printf 0 ;;
  esac
}

# The shell deletes a backslash and the newline after it, so `.s\<newline>sh` is
# one word. Inside single quotes and a quoted heredoc it does not: the client
# gets both lines, and `DROP\<newline>DATABASE` is a verb and a noun. The
# command is read both ways, the pair deleted and the pair a space, and the
# stricter verdict stands.
guard_decide() { # <command>
  local joiner scan verdict strictest=''
  for joiner in '' ' '; do
    scan=$(guard_normalize "$1" "$joiner")
    scan=$(guard_drop_exempt_tokens "$scan")
    verdict=$(guard_classify "$scan")
    if (($(guard_rank "$verdict") > $(guard_rank "$strictest"))); then
      strictest=$verdict
    fi
  done
  printf '%s' "$strictest"
}

guard_main() {
  local rc=0 command verdict

  # The guard is registered on Bash alone, so an input without a command string
  # means the wiring is wrong, not that the call is safe.
  command=$(jq -er 'if (.tool_input.command | type) == "string" then .tool_input.command else error("no Bash command") end' 2>/dev/null) || rc=$?
  if ((rc != 0)); then
    guard_emit deny "$guard_subject could not read its input as a Bash tool call (jq exit $rc), so the call is denied.

$guard_override_advice"
  fi

  verdict=$(guard_decide "$command")

  case $verdict in
  '')
    guard_pass
    ;;
  'ask '*)
    guard_emit ask "$guard_subject cannot tell what this command reaches, so it is asking before the call runs.

Rule: ${verdict#ask }
What looked unresolvable: $guard_ask_why
Command: $command

$guard_advice

If you are an agent and this was denied, write the path or statement out literally so the guard can read it, or tell your user. If a human approves it, nothing more is needed."
    ;;
  'deny '*)
    guard_emit deny "$guard_subject denied this command.

Rule: ${verdict#deny }
Command: $command

$guard_advice

$guard_override_advice"
    ;;
  *)
    guard_emit deny "$guard_subject could not decide this command, because its matcher failed ($verdict). A guard that cannot finish denies.

Command: $command

$guard_override_advice"
    ;;
  esac
}
