# shellcheck shell=bash
# Sourced by the tests/mutate*.sh runners. Each mutant runs in the background in
# its own directory; the results print in declaration order once all are done.
# Env: MUTATE_JOBS caps the mutants that run at once (default: the CPU count).
#      MUTATE_ONLY=<regex> runs only the mutants whose description matches; the
#      run fails when none does.
#      MUTATE_BASE=<rev> runs the mutants only when a path the runner declared
#      with mutate_inputs, or one of .github/workflows/, flake.nix and
#      flake.lock, changed since its merge base with <rev>. A diff that cannot be
#      computed runs them all; the baseline runs either way.
#      MUTATE_OS=linux|macos runs only the mutants whose OSes name that one; one
#      this host cannot run then fails the run instead of reading n/a.
#      MUTATE_SHARD=<k>/<n> runs only the mutants whose declaration index i,
#      counted from 0 over every mutant the runner declares, has i % n == k.
#      MUTATE_LIST=1 prints the inputs and each mutant with its OSes, running
#      nothing.
# A runner calls mutate_inputs, then mutate_baseline, then mutant or
# clean_mutant once per mutant, then mutate_finish. Before declaring a mutant it
# may set mutate_runs_on (default: linux) to the OSes whose CI run must catch
# it, and mutate_host_lacks to why this host cannot run it.

# The physical path: a `path:` flakeref refuses a directory reached through a
# symlink, and macOS puts mktemp's directory under /var, a link to /private/var.
mutate_dir=$(cd "$(mktemp -d)" && pwd -P)
mutate_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
mutate_jobs=${MUTATE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)}
if ! [[ $mutate_jobs =~ ^[1-9][0-9]*$ ]]; then
  echo "MUTATE_JOBS must be a positive integer, got '$mutate_jobs'" >&2
  exit 2
fi
mutate_shard_index=0 mutate_shard_count=1
if [[ -n ${MUTATE_SHARD-} ]]; then
  if ! [[ $MUTATE_SHARD =~ ^([0-9]+)/([1-9][0-9]*)$ ]] || ((BASH_REMATCH[1] >= BASH_REMATCH[2])); then
    echo "MUTATE_SHARD must be <k>/<n> with 0 <= k < n, got '$MUTATE_SHARD'" >&2
    exit 2
  fi
  mutate_shard_index=${BASH_REMATCH[1]} mutate_shard_count=${BASH_REMATCH[2]}
fi
mutate_slots=0
mutate_declared=0
mutate_unselected=0
mutate_shard_skipped=0
mutate_diff_skipped=0
mutate_os_skipped=0
mutate_listed=0
mutate_baseline_passed=
mutate_input_paths=()
mutate_mode=full
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

# Every path a mutant copies or its test reads, relative to the repository; a
# directory stands for everything below it.
mutate_inputs() { # <path>...
  mutate_input_paths+=("$@")
}

# Succeeds when a path on stdin, each ended by a NUL as `git diff -z` prints
# them, is an input, or a path whose change runs every runner.
mutate_inputs_changed() { # <paths
  local path input
  while IFS= read -r -d '' path; do
    [[ -n $path ]] || continue
    for input in .github/workflows flake.nix flake.lock "${mutate_input_paths[@]}"; do
      input=${input%/}
      [[ $path == "$input" || $path == "$input"/* ]] && return 0
    done
  done
  return 1
}

mutate_select() {
  if [[ -z ${MUTATE_BASE-} ]]; then
    echo "mode: full (MUTATE_BASE is unset)"
  elif ! git -C "$mutate_repo" -c core.quotePath=false diff --name-only -z --no-renames "$MUTATE_BASE...HEAD" \
    >"$mutate_dir/changed" 2>"$mutate_dir/changed.err"; then
    echo "mode: full (no diff against $MUTATE_BASE: $(head -n 1 "$mutate_dir/changed.err"))"
  elif mutate_inputs_changed <"$mutate_dir/changed"; then
    echo "mode: full (an input changed since $MUTATE_BASE)"
  else
    mutate_mode=none
    echo "mode: none (no input changed since $MUTATE_BASE)"
  fi
}

mutate_baseline() { # <what> <command>...; exits unless the command passes
  local what=$1 out input
  shift
  if ((${#mutate_input_paths[@]} == 0)); then
    echo "FAIL: the runner declares no inputs, so no diff can select it" >&2
    exit 2
  fi
  if [[ -n ${MUTATE_LIST-} ]]; then
    for input in "${mutate_input_paths[@]}"; do
      echo "input: $input"
    done
    mutate_baseline_passed=1
    return 0
  fi
  mutate_select
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

mutate_on() { # <OSes> <command>...: the mutants <command> declares run on <OSes>
  local mutate_runs_on=$1
  "${@:2}"
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
  local runs_on=${mutate_runs_on:-linux}
  mutate_declared=$((mutate_declared + 1))
  if (((mutate_declared - 1) % mutate_shard_count != mutate_shard_index)); then
    mutate_shard_skipped=$((mutate_shard_skipped + 1))
    return 0
  fi
  if [[ -n ${MUTATE_ONLY-} ]] && ! [[ $description =~ $MUTATE_ONLY ]]; then
    mutate_unselected=$((mutate_unselected + 1))
    return 0
  fi
  if [[ -n ${MUTATE_LIST-} ]]; then
    mutate_listed=$((mutate_listed + 1))
    echo "mutant: $runs_on: $description"
    return 0
  fi
  if [[ $mutate_mode == none ]]; then
    mutate_diff_skipped=$((mutate_diff_skipped + 1))
    return 0
  fi
  if [[ -n ${MUTATE_OS-} && " $runs_on " != *" $MUTATE_OS "* ]]; then
    mutate_os_skipped=$((mutate_os_skipped + 1))
    return 0
  fi
  if [[ -n ${mutate_host_lacks-} ]]; then
    if [[ -n ${MUTATE_OS-} ]]; then
      mutate_fail "FAIL: '$description' must run on $MUTATE_OS, but $mutate_host_lacks"
    else
      mutate_na "$description: $mutate_host_lacks"
    fi
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
  if [[ -n ${MUTATE_SHARD-} ]]; then
    echo "shard $MUTATE_SHARD: selected $((mutate_declared - mutate_shard_skipped)) of $mutate_declared"
  fi
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
  if [[ -n ${MUTATE_LIST-} ]]; then
    echo "listed $mutate_listed mutant(s)"
    exit 0
  fi
  ((mutate_diff_skipped == 0)) || summary="$summary; skipped $mutate_diff_skipped, no input changed"
  ((mutate_os_skipped == 0)) || summary="$summary; skipped $mutate_os_skipped that run on another OS"
  if ((failed > 0)); then
    echo "$failed mutation check(s) failed ($summary)"
    exit 1
  fi
  if ((caught + clean == 0)); then
    if [[ -z ${MUTATE_ONLY-} ]] && ((mutate_diff_skipped + mutate_os_skipped + mutate_shard_skipped > 0)); then
      echo "no mutant runs here, and the baseline passed ($summary)"
      exit 0
    fi
    echo "no mutant ran ($summary)"
    exit 1
  fi
  echo "every mutant is caught ($summary)"
}
