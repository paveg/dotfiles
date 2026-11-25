# The engine shared by the guards of docs/adr/0007-agent-guardrails.md.
# nix/agents.nix concatenates this file in front of a guard, which sets
# guard_subject, guard_patterns, guard_stems and guard_advice and then calls
# guard_main. writeShellApplication supplies the shebang, errexit, nounset,
# pipefail and the pinned PATH, so nothing here resolves a dependency from the
# caller's PATH.
#
# The contract: a guard prints a PreToolUse deny decision when it matches, when
# it cannot read its input, and when its matcher errors, and prints nothing at
# all otherwise. It never prints `allow`, which would skip the permission
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

# Anything a shell expands and a matcher cannot. Quotes, backslashes and
# newlines are gone by the time a pattern runs, but one of these can still hold
# a protected name apart or build one at run time.
guard_expansion='[$`*?[{]'

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

# The whole-command rule. The exact patterns above read a command as written;
# this one answers whether it can be read at all. It prints `unresolved <stem>`
# when the command both names something the guard protects and uses an
# expansion, in either order and anywhere in the command, and nothing
# otherwise. Same grep contract as guard_classify, and the same reason for not
# deciding anything itself.
guard_classify_unresolved() { # <normalized-command>
  local scan=$1 stem rc=0
  grep -qE -e "$guard_expansion" <<<"$scan" 2>/dev/null || rc=$?
  case $rc in
  0) ;;
  1) return 0 ;;
  *)
    printf 'error %s grep-exit-%s' "$guard_expansion" "$rc"
    return 0
    ;;
  esac
  for stem in "${guard_stems[@]}"; do
    rc=0
    grep -qE -e "${guard_name_start}${stem}" <<<"$scan" 2>/dev/null || rc=$?
    case $rc in
    0)
      printf 'unresolved %s' "$stem"
      return 0
      ;;
    1) ;;
    *)
      printf 'error %s grep-exit-%s' "$stem" "$rc"
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
  scan=$(guard_drop_exempt_tokens "$scan")
  verdict=$(guard_classify "$scan")
  if [[ -z $verdict ]]; then
    verdict=$(guard_classify_unresolved "$scan")
  fi

  case $verdict in
  '')
    guard_pass
    ;;
  'unresolved '*)
    guard_deny "$guard_subject could not resolve the command statically; it mentions ${verdict#unresolved } and uses shell expansion, which only a shell could work out. A guard that cannot read a command denies it.

Command: $command

$guard_advice

$guard_override_advice"
    ;;
  'match '*)
    pattern=${verdict#match }
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
