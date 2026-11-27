#!/usr/bin/env bash
# Check, by evaluation alone, that everything a host installs may be used on
# the work machine: home.packages, and on macOS the system packages, fonts, and
# Homebrew casks and formulae, plus the Windows-side installs that design.md
# names for wsl. Prints a table of each item, its licence, and the verdict.
# A check fails on a licence with an NC (non-commercial) id or a full name that
# says non-commercial, allowed by name or not; on an unfree or
# non-redistributable one that flake.nix does not allow by name; on a Nix
# package with no meta.license that nix/licenses.nix does not record; on an
# install from outside Nix that nix/licenses.nix has no entry for; on a
# `winget install` it cannot parse; and on a cask, brew, or mas line in
# homebrew.extraConfig. The licence of a package's dependencies is not checked.
# Usage: tests/licenses.sh [repo-dir]
# Env: DOTFILES_HOST selects the host (default: personal-mac on macOS, wsl
#      elsewhere).
set -uo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_dir=${1:-$script_dir/..}
# Physical path: a `path:` flake reference rejects one that crosses a symlink.
repo_dir=$(cd "$repo_dir" && pwd -P)
default_host=wsl
[[ $(uname -s) == Darwin ]] && default_host=personal-mac
host=${DOTFILES_HOST:-$default_host}

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# --impure for getFlake on an unlocked path:, which takes an uncommitted or
# copied tree as it is. Ceiling: the whole evaluation is then impure, so the
# wsl pkgs pick up the caller's nixpkgs overlays (<nixpkgs-overlays>,
# ~/.config/nixpkgs/overlays[.nix]), which the pure build does not see; CI has
# none.
rows=$(nix --extra-experimental-features 'nix-command flakes' eval --raw --impure --expr \
  "import $script_dir/licenses.nix { flake = builtins.getFlake \"path:$repo_dir\"; host = \"$host\"; }" \
  2>"$work_dir/eval.err")
if [[ -z $rows ]]; then
  echo "FAIL: evaluate: $(tr '\n' ' ' <"$work_dir/eval.err" | cut -c1-600)"
  echo "summary: 0 items, 1 failed (host $host, repo $repo_dir)"
  exit 1
fi

items=0
failures=0
failed=()
table_row() { # <source> <package> <licence> <verdict>
  printf '%-8s %-36s %-30s %s\n' "$@"
}

table_row source package licence verdict
while IFS='|' read -r source name license note rules; do
  items=$((items + 1))
  if [[ -n $rules ]]; then
    verdict="FAIL $rules"
    for rule in $rules; do
      failed+=("FAIL: $rule-$host-$name: $source, $license")
    done
    failures=$((failures + 1))
  else
    verdict=ok${note:+ ($note)}
  fi
  table_row "$source" "$name" "$license" "$verdict"
done <<<"$rows"

if ((${#failed[@]} > 0)); then
  printf '%s\n' "${failed[@]}"
fi
echo "summary: $items items, $failures failed (host $host, repo $repo_dir)"
if ((failures > 0)); then exit 1; fi
