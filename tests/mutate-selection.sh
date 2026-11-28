#!/usr/bin/env bash
# Break one condition of the runner selection at a time: of tests/lib/mutate.sh,
# which tests/selection.sh must catch, of the workflow selection in
# tests/workflow-changed.sh and that helper, which tests/workflow-selection.sh
# must catch, and of what a runner declares, which tests/mutation-coverage.sh
# must catch.
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

# Copies of tests/workflow-changed.sh and the helper, with <file> broken by
# each <old> <new> pair in turn.
run_workflow_selection() { # <dir> <check>... <file> <old> <new> [<old> <new>]...
  local dir=$1 checks=$2 file=$3 out
  shift 3
  cp "$repo_dir/tests/workflow-changed.sh" "$repo_dir/$lib" "$dir/"
  while (($# >= 2)); do
    mutate_apply "$dir/${file##*/}" "$1" "$2" || return
    shift 2
  done
  out=$("$repo_dir/tests/workflow-selection.sh" "$dir/workflow-changed.sh" "$dir/mutate.sh" 2>&1) || true
  mutate_has_summary "$out" || return
  # shellcheck disable=SC2086 # one check name per word
  mutate_checks_failed "$out" $checks
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
# under every top-level directory; the mutants take seconds.
mutate_inputs tests .github/workflows nix home docs hosts profiles scripts spec flake.nix flake.lock
selection_tests() { "$repo_dir/tests/selection.sh" && "$repo_dir/tests/workflow-selection.sh"; }
mutate_baseline 'the selection as committed' selection_tests

mutant 'an input matches every path it is a prefix of' run_selection \
  'sibling-of-input-file prefix-of-input-directory' \
  '[[ $path == "$input" || $path == "$input"/* ]] && return 0' '[[ $path == "$input"* ]] && return 0'
mutant 'a workflow or flake change runs only the runners it is an input of' run_selection \
  'workflow flake-lock flake-nix' \
  'for input in .github/workflows flake.nix flake.lock "${mutate_input_paths[@]}"; do' \
  'for input in "${mutate_input_paths[@]}"; do'
mutant 'a diff that cannot be computed runs nothing' run_selection unknown-diff-runs-everything \
  '    echo "mode: full (no diff against' '    mutate_mode=none; echo "mode: full (no diff against'

workflow=tests/workflow-changed.sh
mutant 'a workflow leaves out a path its paths filter matched' run_workflow_selection hooks-runs \
  "$workflow" 'nix/ghtkn-render.sh hosts tests/hooks.sh' 'nix/ghtkn-render.sh tests/hooks.sh'
mutant 'a change to the workflow selection runs only the workflows that name it' run_workflow_selection \
  'hooks-runs agents-runs spec-runs' "$workflow" 'mutate_inputs tests/workflow-changed.sh tests/lib' ':'
mutant 'a workflow or flake change runs only the workflows that name it' run_workflow_selection \
  'shell-runs hooks-runs agents-runs nix-runs spec-runs' "$lib" \
  'for input in .github/workflows flake.nix flake.lock "${mutate_input_paths[@]}"; do' \
  'for input in "${mutate_input_paths[@]}"; do'
mutant 'a pull request that changes no input runs every workflow' run_workflow_selection \
  'shell-skips hooks-skips agents-skips nix-skips spec-skips' "$workflow" \
  'if [[ $mutate_mode == none ]]; then' 'if false; then'
mutant 'an unset MUTATE_BASE runs only the workflows whose inputs changed' run_workflow_selection push-runs \
  "$lib" '    echo "mode: full (MUTATE_BASE is unset)"' '    mutate_mode=none; echo "mode: full (MUTATE_BASE is unset)"'
mutant 'a diff that cannot be computed skips the workflow' run_workflow_selection \
  'unknown-base-runs no-merge-base-runs shallow-clone-runs' "$lib" \
  '    echo "mode: full (no diff against' '    mutate_mode=none; echo "mode: full (no diff against'
mutant 'the changed paths are read a line at a time' run_workflow_selection unusual-name-runs "$lib" \
  'diff --name-only -z --no-renames' 'diff --name-only --no-renames' \
  "while IFS= read -r -d '' path; do" 'while IFS= read -r path; do'
mutant 'an unknown workflow decides on the inputs every workflow takes in' run_workflow_selection \
  unknown-workflow-fails "$workflow" '  exit 2' '  :'

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
