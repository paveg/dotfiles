#!/usr/bin/env bash
# Print changed=false when no input of <workflow> changed since the merge base
# of HEAD with MUTATE_BASE, and changed=true otherwise: when one did, when the
# diff cannot be computed, and when MUTATE_BASE is unset. The diff and the
# paths every workflow takes in (.github/workflows/, flake.nix, flake.lock) are
# tests/lib/mutate.sh's, as for the mutation runners.
# Usage: MUTATE_BASE=<rev> tests/workflow-changed.sh <workflow> >>"$GITHUB_OUTPUT"
set -euo pipefail
# shellcheck source=tests/lib/mutate.sh
source "$(dirname "$0")/lib/mutate.sh"

# This script and its helper decide for every workflow, so a change to either
# runs them all.
mutate_inputs tests/workflow-changed.sh tests/lib
case ${1-} in
shell) mutate_inputs home nix profiles tests scripts/pre-wipe-inventory.sh ;;
hooks)
  mutate_inputs home/.claude/hooks nix/agents.nix hosts tests/hooks.sh tests/mutate-hooks.sh \
    tests/fixtures/hooks tests/reply-language.sh tests/fixtures/reply-language
  ;;
agents) mutate_inputs home hosts nix profiles tests/agents.sh tests/mutate-agents.sh tests/auto-mode.expected.json ;;
nix) mutate_inputs docs/design.md home hosts nix tests ;;
spec) mutate_inputs spec ;;
*)
  echo "unknown workflow '${1-}': want shell, hooks, agents, nix or spec" >&2
  exit 2
  ;;
esac
mutate_select >&2
if [[ $mutate_mode == none ]]; then
  echo changed=false
else
  echo changed=true
fi
