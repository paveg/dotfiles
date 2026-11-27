#!/usr/bin/env bash
# Break one condition of the runner selection at a time: of tests/lib/mutate.sh,
# which tests/selection.sh must catch, and of what a runner declares, which
# tests/mutation-coverage.sh must catch.
# SC2016: each mutation target is literal source text, not an expansion.
# shellcheck disable=SC2016
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/mutate.sh
source "$repo_dir/tests/lib/mutate.sh"

run_selection() { # <dir> <check>... <old> <new>
  local out
  mkdir -p "$1/lib"
  cp "$repo_dir/tests/lib/mutate.sh" "$1/lib/mutate.sh"
  mutate_apply "$1/lib/mutate.sh" "$3" "$4" || return
  out=$("$repo_dir/tests/selection.sh" "$1/lib/mutate.sh" 2>&1) || true
  mutate_has_summary "$out" || return
  # shellcheck disable=SC2086 # one check name per word
  mutate_checks_failed "$out" $2
}

# A copy of tests/ and .github/ beside links to the rest of the checkout.
run_coverage() { # <dir> <check>... <file> <old> <new>
  local entry out
  for entry in "$repo_dir"/* "$repo_dir"/.github; do
    case ${entry##*/} in
    tests | .github) cp -R "$entry" "$1/" ;;
    *) ln -s "$entry" "$1/${entry##*/}" ;;
    esac
  done
  mutate_apply "$1/$3" "$4" "$5" || return
  out=$("$1/tests/mutation-coverage.sh" "$1" 2>&1) || true
  mutate_has_summary "$out" || return
  # shellcheck disable=SC2086 # one check name per word
  mutate_checks_failed "$out" $2
}

lib=tests/lib/mutate.sh

# The coverage copies link the rest of the checkout, and the fixtures name paths
# under nix/, home/ and docs/; the mutants take seconds.
mutate_inputs tests .github/workflows nix home docs flake.nix flake.lock
mutate_baseline 'the selection as committed' "$repo_dir/tests/selection.sh"

mutant 'an input matches every path it is a prefix of' run_selection \
  'sibling-of-input-file prefix-of-input-directory' \
  '[[ $path == "$input" || $path == "$input"/* ]] && return 0' '[[ $path == "$input"* ]] && return 0'
mutant 'a workflow or flake change runs only the runners it is an input of' run_selection \
  'workflow flake-lock flake-nix' \
  'for input in .github/workflows flake.nix flake.lock "${mutate_input_paths[@]}"; do' \
  'for input in "${mutate_input_paths[@]}"; do'
mutant 'a diff that cannot be computed runs nothing' run_selection unknown-diff-runs-everything \
  '    echo "mode: full (no diff against' '    mutate_mode=none; echo "mode: full (no diff against'

mutant 'a runner leaves its subject out of its inputs' run_coverage inputs-mutate-ssh.sh \
  tests/mutate-ssh.sh 'mutate_inputs nix/ssh_config tests/ssh.sh' 'mutate_inputs tests/ssh.sh'
mutant 'a mutant names an OS no workflow runs its runner on' run_coverage run-mutate-ssh.sh \
  tests/mutate-ssh.sh "mutate_runs_on='linux macos'" "mutate_runs_on='macOS'"
mutant 'a workflow stops running a runner on an OS one of its mutants declares' run_coverage run-mutate-ssh.sh \
  .github/workflows/shell.yml 'MUTATE_OS=macos tests/mutate-ssh.sh' 'true'
mutant 'a shard also takes the mutants of the shards before it' run_coverage \
  'shards-mutate-ssh.sh shards-mutate.sh shards-mutate-hooks.sh' \
  "$lib" '(((mutate_declared - 1) % mutate_shard_count != mutate_shard_index))' \
  '(((mutate_declared - 1) % mutate_shard_count > mutate_shard_index))'

mutate_finish
