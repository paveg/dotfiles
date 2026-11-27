# shellcheck shell=bash
# Sourced by the tests/mutate*.sh runners. Each mutant runs in the background in
# its own directory; the results print in declaration order once all are done.
# Env: MUTATE_JOBS caps the mutants that run at once (default: the CPU count).
#      MUTATE_ONLY=<regex> runs only the mutants whose description matches; the
#      run fails when none does.
# A runner calls mutate_baseline, then mutant or clean_mutant once per mutant,
# then mutate_finish.

# The physical path: a `path:` flakeref refuses a directory reached through a
# symlink, and macOS puts mktemp's directory under /var, a link to /private/var.
mutate_dir=$(cd "$(mktemp -d)" && pwd -P)
mutate_jobs=${MUTATE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)}
if ! [[ $mutate_jobs =~ ^[1-9][0-9]*$ ]]; then
  echo "MUTATE_JOBS must be a positive integer, got '$mutate_jobs'" >&2
  exit 2
fi
mutate_slots=0
mutate_unselected=0
mutate_baseline_passed=
mutate_slot_kind=()
mutate_slot_text=()
mutate_slot_verb=()

# A tree, not a pid: the test scripts, zsh and nix below a mutant ignore the
# SIGINT a Ctrl-C sends, as every background job of a non-interactive shell does.
# Leaves go first, so a test script's EXIT trap removes its directory after
# nothing is left to write there. HUP rather than TERM, which zsh -i ignores.
mutate_kill_tree() { # <pid>
  local child
  kill -STOP "$1" 2>/dev/null || return 0
  for child in $(pgrep -P "$1"); do
    mutate_kill_tree "$child"
  done
  kill -HUP "$1" 2>/dev/null
  kill -CONT "$1" 2>/dev/null
}

mutate_cleanup() {
  local pid
  set +e
  for pid in $(jobs -p); do
    mutate_kill_tree "$pid"
  done
  wait 2>/dev/null
  rm -rf "$mutate_dir"
}
trap mutate_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mutate_baseline() { # <what> <command>...; exits unless the command passes
  local what=$1 out
  shift
  if out=$("$@" 2>&1); then
    echo "pass: $what"
    mutate_baseline_passed=1
  else
    echo "FAIL: $what should pass"
    grep -E '^(ERROR|FAIL)' <<<"$out" | head -5
    exit 1
  fi
}

# Replace the one occurrence of <old> in <file> with <new>; fails unless there
# is exactly one.
mutate_apply() { # <file> <old> <new>
  OLD=$2 NEW=$3 python3 - "$1" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
}

# For <output> of a test run, succeeds when every <check> printed a FAIL line.
mutate_checks_failed() { # <output> <check>...
  local out=$1 check missing=
  shift
  for check; do
    grep -q "^FAIL: $check:" <<<"$out" || missing="$missing $check"
  done
  [[ -z $missing ]] && return 0
  echo "expected to fail:$missing"
  grep -E '^(FAIL|ERROR|summary)' <<<"$out" | head -5
  return 1
}

# The summary line proves the run reached the end: a crash that skips later
# checks is a broken harness, not a caught mutant.
mutate_has_summary() { # <output>
  grep -q '^summary:' <<<"$1" && return 0
  echo "no summary line"
  grep -E '^(FAIL|ERROR)' <<<"$1" | head -5
  return 1
}

mutate_slot() { # <kind> <text>
  mutate_slots=$((mutate_slots + 1))
  mutate_slot_kind[mutate_slots]=$1
  mutate_slot_text[mutate_slots]=$2
}

# An n/a line, in declaration order: mutants this host cannot run.
mutate_na() { # <reason>
  mutate_slot na "n/a: $1"
}

# A failure of the runner itself, in declaration order.
mutate_fail() { # <line>
  mutate_slot fail "$1"
}

# Run `<function> <dir> <arg>...` in the background, where <dir> is an empty
# directory of the mutant's own. The function succeeds when the mutant is
# caught; what it prints shows under the MISSED line.
mutant() { # <description> <function> <arg>...
  mutate_spawn caught "$@"
}

# As mutant, for a mutant the checks must pass: success prints "clean:".
clean_mutant() { # <description> <function> <arg>...
  mutate_spawn clean "$@"
}

mutate_spawn() { # <verb> <description> <function> <arg>...
  local verb=$1 description=$2 dir
  shift 2
  if [[ -z $mutate_baseline_passed ]]; then
    echo "FAIL: mutant '$description' was declared before the files as committed passed" >&2
    exit 1
  fi
  if [[ -n ${MUTATE_ONLY-} ]] && ! [[ $description =~ $MUTATE_ONLY ]]; then
    mutate_unselected=$((mutate_unselected + 1))
    return 0
  fi
  mutate_slot mutant "$description"
  mutate_slot_verb[mutate_slots]=$verb
  dir=$mutate_dir/$mutate_slots
  mkdir -p "$dir/tree"
  while (($(jobs -pr | wc -l) >= mutate_jobs)); do
    sleep 0.1
  done
  (
    set +e
    (
      set -e
      "$1" "$dir/tree" "${@:2}"
    ) >"$dir/out" 2>&1
    echo $? >"$dir/status"
  ) &
}

# $mutate_context, when set, is added to the last line.
mutate_finish() {
  local n dir status caught=0 clean=0 failed=0 na=0 selected=0 summary
  wait
  for ((n = 1; n <= mutate_slots; n++)); do
    case ${mutate_slot_kind[n]} in
    na)
      na=$((na + 1))
      echo "${mutate_slot_text[n]}"
      ;;
    fail)
      failed=$((failed + 1))
      echo "${mutate_slot_text[n]}"
      ;;
    mutant)
      selected=$((selected + 1))
      dir=$mutate_dir/$n
      status=$(cat "$dir/status" 2>/dev/null) || status=missing
      if [[ $status != 0 ]]; then
        failed=$((failed + 1))
        echo "MISSED: ${mutate_slot_text[n]} (exit $status)"
        cat "$dir/out"
      elif [[ ${mutate_slot_verb[n]} == clean ]]; then
        clean=$((clean + 1))
        echo "clean: ${mutate_slot_text[n]}"
      else
        caught=$((caught + 1))
        echo "caught: ${mutate_slot_text[n]}"
      fi
      ;;
    esac
  done
  summary="$caught caught"
  ((clean == 0)) || summary="$summary, $clean clean"
  ((na == 0)) || summary="$summary, $na n/a"
  [[ -z ${mutate_context-} ]] || summary="$summary, $mutate_context"
  if [[ -n ${MUTATE_ONLY-} ]]; then
    summary="$summary; MUTATE_ONLY selected $selected, skipped $mutate_unselected"
  fi
  if ((failed > 0)); then
    echo "$failed mutation check(s) failed ($summary)"
    exit 1
  fi
  if ((caught + clean == 0)); then
    echo "no mutant ran ($summary)"
    exit 1
  fi
  echo "every mutant is caught ($summary)"
}
