#!/usr/bin/env bash
# Check how tests/workflow-changed.sh decides whether a workflow's checks run on
# a pull request, through git in a throwaway repository. For each workflow, a
# change to a path its pull_request paths filter matched before every workflow
# ran on every pull request runs it, one path per entry of that filter, and so
# does a change to the decision itself; README.md or docs/adr/ alone does not.
# An unset MUTATE_BASE, a base git does not know, a base with no merge base, a
# shallow clone, an input whose name git would quote, a deleted input and an
# input moved out of the inputs all run it, every workflow guards the decision
# code against deciding for itself, and an unknown workflow name fails.
# Usage: tests/workflow-selection.sh [script [helper]]
#        (default: tests/workflow-changed.sh and tests/lib/mutate.sh)
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
script=${1:-$repo_dir/tests/workflow-changed.sh}
helper=${2:-$repo_dir/tests/lib/mutate.sh}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
repo=$work_dir/repo
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fixture_git() { git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }

checks=0
failures=0

ok() { # <name>
  checks=$((checks + 1))
  echo "ok: $1"
}

fail() { # <name> <detail>
  checks=$((checks + 1))
  failures=$((failures + 1))
  echo "FAIL: $1: $2"
}

# main holds the script and its helper, where the script looks for them.
fixture_git init -q -b main "$repo"
mkdir -p "$repo/tests/lib"
cp "$script" "$repo/tests/workflow-changed.sh"
cp "$helper" "$repo/tests/lib/mutate.sh"
echo base >"$repo/README.md"
mkdir -p "$repo/home"
echo kept >"$repo/home/kept"
fixture_git -C "$repo" add -A
fixture_git -C "$repo" commit -qm base

# HEAD becomes the branch case: main plus a change to each <path>.
change() { # <path>...
  local path
  fixture_git -C "$repo" checkout -qf -B case main
  for path; do
    mkdir -p "$(dirname "$repo/$path")"
    echo '# case' >>"$repo/$path"
  done
  fixture_git -C "$repo" add -A
  fixture_git -C "$repo" commit -qm case
}

# What the script prints for <workflow> in <checkout>, run under `env <env>...`.
decide() { # <checkout> <workflow> <env>...
  local checkout=$1 workflow=$2
  shift 2
  env "$@" bash "$checkout/tests/workflow-changed.sh" "$workflow" 2>/dev/null
}

# Each <path>, changed alone, must print changed=<want> for <workflow>.
expect() { # <name> <workflow> <true|false> <path>...
  local name=$1 workflow=$2 want=$3 path got wrong=
  shift 3
  for path; do
    change "$path"
    got=$(decide "$repo" "$workflow" MUTATE_BASE=main)
    [[ $got == "changed=$want" ]] || wrong="$wrong $path(${got:-nothing})"
  done
  if [[ -z $wrong ]]; then
    ok "$name"
  else
    fail "$name" "want changed=$want for$wrong"
  fi
}

# What every workflow takes in, then each workflow's old paths filter.
every=(flake.nix flake.lock .github/workflows/case.yml tests/workflow-changed.sh tests/lib/mutate.sh)
expect shell-runs shell true "${every[@]}" home/case nix/case profiles/case tests/case scripts/pre-wipe-inventory.sh
expect hooks-runs hooks true "${every[@]}" home/.claude/hooks/case nix/agents.nix nix/ghtkn.nix nix/gh.sh nix/ghtkn-render.sh hosts/case.nix tests/hooks.sh \
  tests/mutate-hooks.sh tests/fixtures/hooks/case tests/reply-language.sh tests/fixtures/reply-language/case
expect agents-runs agents true "${every[@]}" home/case hosts/case.nix nix/case profiles/case tests/agents.sh \
  tests/mutate-agents.sh tests/auto-mode.expected.json
expect nix-runs nix true "${every[@]}" docs/design.md home/case hosts/case.nix nix/case tests/case
expect spec-runs spec true "${every[@]}" spec/case
for workflow in shell hooks agents nix spec; do
  expect "$workflow-skips" "$workflow" false README.md docs/adr/case.md
done

is() { # <name> <want> <got>
  if [[ $3 == "$2" ]]; then ok "$1"; else fail "$1" "want '$2', got '$3'"; fi
}

change README.md
is push-runs changed=true "$(decide "$repo" shell -u MUTATE_BASE)"
is unknown-base-runs changed=true "$(decide "$repo" shell MUTATE_BASE=refs/heads/no-such-branch)"

fixture_git -C "$repo" checkout -q --orphan unrelated
fixture_git -C "$repo" rm -qrf .
echo other >"$repo/other"
fixture_git -C "$repo" add other
fixture_git -C "$repo" commit -qm unrelated
change README.md
is no-merge-base-runs changed=true "$(decide "$repo" shell MUTATE_BASE=unrelated)"

# A depth-1 clone holds both tips but not the commit they fork from.
fixture_git -C "$repo" checkout -qf -B moved main
echo moved >>"$repo/README.md"
fixture_git -C "$repo" commit -qam moved
change README.md
fixture_git -c protocol.file.allow=always clone -q --depth 1 --no-single-branch --branch case \
  "file://$repo" "$work_dir/shallow"
is shallow-clone-runs changed=true "$(decide "$work_dir/shallow" shell MUTATE_BASE=origin/moved)"

# Without -z, git quotes this path, and the quoted name is under no input.
change $'home/new\nline \xc3\xa9'
is unusual-name-runs changed=true "$(decide "$repo" shell MUTATE_BASE=main)"

# Deleting an input, or moving it out of the inputs, changes it.
fixture_git -C "$repo" checkout -qf -B case main
fixture_git -C "$repo" rm -q home/kept
fixture_git -C "$repo" commit -qm case
is delete-runs changed=true "$(decide "$repo" shell MUTATE_BASE=main)"
fixture_git -C "$repo" checkout -qf -B case main
mkdir -p "$repo/docs"
fixture_git -C "$repo" mv home/kept docs/kept
fixture_git -C "$repo" commit -qm case
is rename-out-runs changed=true "$(decide "$repo" shell MUTATE_BASE=main)"

# The changes job of every workflow runs every check when the decision code
# changed, before the pull request's own copy of it decides.
for workflow in shell hooks agents nix spec; do
  file=$repo_dir/.github/workflows/$workflow.yml
  if grep -qF 'git diff --quiet "origin/$BASE...HEAD" -- tests/workflow-changed.sh tests/lib' "$file" &&
    grep -qF "changed: \${{ steps.guard.outputs.self == 'true' && 'true' || steps.inputs.outputs.changed }}" "$file"; then
    ok "$workflow-guards-its-decision"
  else
    fail "$workflow-guards-its-decision" "$file lacks the guard on tests/workflow-changed.sh and tests/lib"
  fi
done

change README.md
out=$(decide "$repo" no-such-workflow MUTATE_BASE=main)
status=$?
is unknown-workflow-fails "exit non-zero, printed ''" "exit $([[ $status == 0 ]] && echo 0 || echo non-zero), printed '$out'"

echo "summary: $checks checks, $failures failed"
((failures == 0))
