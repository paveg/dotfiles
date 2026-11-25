# The engine shared by the guards of docs/adr/0007-agent-guardrails.md.
# nix/agents.nix concatenates this file in front of a guard, which sets
# guard_subject, guard_patterns and guard_advice and then calls guard_main.
# writeShellApplication supplies the shebang, errexit, nounset, pipefail and the
# pinned PATH, so nothing here resolves a dependency from the caller's PATH.
#
# The contract: a guard prints a PreToolUse deny decision when it matches, when
# it cannot read its input, and when its matcher errors, and prints nothing at
# all otherwise. It never prints `allow`, which would skip the permission
# prompt, and exit 0 with no output is not an approval.

shopt -s inherit_errexit

guard_finished=0

# Tokens a guard treats as safe whole words, such as a committed .env template.
# A guard that has none leaves this empty.
guard_exempt_suffixes=()

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

guard_deny() { # <reason>
  local json
  json=$(jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
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

# Quotes, backslashes and newlines are gone by the time a pattern runs, but a
# glob, a brace, a substitution or a SQL comment can still hold a protected
# name apart, and expanding one needs a shell rather than a matcher. A guard
# therefore also denies when such a construct shares a whitespace-delimited
# word with something it protects: a command it cannot resolve statically is a
# command it cannot clear. Each guard writes that pattern with this group, which
# is also how guard_main tells such a match from a plain one.
guard_unresolvable='([$]|`|--|/\*|\*/|\*|\?|\[|\{)'

# A word that ends in one of the guard's exempt tokens leaves the scan before
# any pattern runs. Matching "every name but these" in one regex needs a
# negative lookahead ERE does not have, and spelling it out by hand let a
# strict prefix (.env.exam) through. Comparing whole tokens cannot.
guard_drop_exempt_words() { # <normalized-command>
  local -a words
  local word suffix kept=
  read -ra words <<<"$1"
  for word in "${words[@]}"; do
    for suffix in "${guard_exempt_suffixes[@]}"; do
      if [[ $word == *"$suffix" ]]; then
        word=
        break
      fi
    done
    if [[ -n $word ]]; then
      kept+="$word "
    fi
  done
  printf '%s' "$kept"
}

# Drop quote and backslash concatenation so that token splitting cannot hide an
# operation, flatten the newlines because grep matches one line at a time, and
# lowercase. Over-normalizing can only add a pause for review; from here there
# is no path to an allow.
guard_normalize() { # <command>
  local text=$1
  text=${text//\"/}
  text=${text//\'/}
  text=${text//\\/}
  text=${text//$'\n'/ }
  printf '%s' "$text" | tr '[:upper:]' '[:lower:]'
}

# Prints `match <pattern>` for the first pattern that matches, `error <pattern>
# grep-exit-<rc>` when the matcher itself fails, and nothing when nothing
# matches. grep returns 1 for no match and 2 or more for an error, and only 1
# counts as no match. This runs inside $(…), where errexit is suspended without
# inherit_errexit, so an unexpected failure aborts instead of reading as "no
# match": it must not print a decision itself.
guard_classify() { # <normalized-command>
  local scan=$1 pattern rc
  for pattern in "${guard_patterns[@]}"; do
    rc=0
    grep -qE -e "$pattern" <<<"$scan" 2>/dev/null || rc=$?
    case $rc in
    0)
      printf 'match %s' "$pattern"
      return 0
      ;;
    1) ;;
    *)
      printf 'error %s grep-exit-%s' "$pattern" "$rc"
      return 0
      ;;
    esac
  done
  return 0
}

guard_main() {
  local rc=0 command scan verdict pattern

  # The guard is registered on Bash alone, so an input without a command string
  # means the wiring is wrong, not that the call is safe.
  command=$(jq -er 'if (.tool_input.command | type) == "string" then .tool_input.command else error("no Bash command") end' 2>/dev/null) || rc=$?
  if ((rc != 0)); then
    guard_deny "$guard_subject could not read its input as a Bash tool call (jq exit $rc), so the call is denied.

$guard_override_advice"
  fi

  scan=$(guard_normalize "$command")
  scan=$(guard_drop_exempt_words "$scan")
  verdict=$(guard_classify "$scan")

  case $verdict in
  '')
    guard_pass
    ;;
  'match '*)
    pattern=${verdict#match }
    if [[ $pattern == *"$guard_unresolvable"* ]]; then
      guard_deny "$guard_subject cannot resolve this command: a name it protects shares a word with a glob, a brace, a substitution or a comment, which only a shell could expand. A guard that cannot read a command denies it.

Command: $command

$guard_advice

$guard_override_advice"
    fi
    guard_deny "$guard_subject denied this command.

Matched pattern: $pattern
Command: $command

$guard_advice

$guard_override_advice"
    ;;
  *)
    guard_deny "$guard_subject could not decide this command, because its matcher failed ($verdict). A guard that cannot finish denies.

Command: $command

$guard_override_advice"
    ;;
  esac
}
