#!/usr/bin/env bash
# Check what the built configuration gives a host, with no Nix switch: every
# global CLI tool is in the home-manager profile and wins over /usr/bin, the zsh
# directory is a real directory of per-file links, and the global mise config
# refuses the asdf backend.
# Usage: tests/packages.sh [repo-dir]
# Env: DOTFILES_HOST selects the host (default: personal-mac on macOS, wsl
#      elsewhere). ZSH_BIN overrides the zsh to test.
set -uo pipefail

repo_dir=${1:-$(cd "$(dirname "$0")/.." && pwd)}
# Physical path: a `path:` flake reference rejects one that crosses a symlink,
# which macOS's /var is.
repo_dir=$(cd "$repo_dir" && pwd -P)
default_host=wsl
[[ $(uname -s) == Darwin ]] && default_host=personal-mac
host=${DOTFILES_HOST:-$default_host}
zsh_bin=${ZSH_BIN:-$(command -v zsh)}
nix_bin=(nix --extra-experimental-features 'nix-command flakes')

# Command names, not package names: what a caller types is the behaviour under
# test. `gh` is not here; it becomes a wrapper in a later change.
commands=(
  claude git ghq fzf rg fd jq nvim just lazygit lefthook gitleaks
  kubectl helm k9s stern ghtkn mise atuin
)
# One link per file, so these directories stay real directories.
linked_files=(
  .config/zsh/.zshenv .config/zsh/.zprofile .config/zsh/.zshrc
  .config/mise/config.toml
)
real_dirs=(.config/zsh .config/mise)

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

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

is() { # <name> <want> <got>
  if [[ $3 == "$2" ]]; then ok "$1"; else fail "$1" "want '$2', got '$3'"; fi
}

user=$("${nix_bin[@]}" eval --raw --file "$repo_dir/hosts/$host.nix" user) || user=
if [[ -z $user ]]; then
  fail host-user "hosts/$host.nix has no user"
  echo "summary: $checks checks, $failures failed (host $host, repo $repo_dir)"
  exit 1
fi
ok host-user

# path: rather than the directory on its own, so an uncommitted or copied tree
# builds the same way a checkout does.
if [[ $host == wsl ]]; then
  config_attr="homeConfigurations.\"$user@wsl\".config"
else
  config_attr="darwinConfigurations.$host.config.home-manager.users.$user"
fi

build() { # <attribute>
  "${nix_bin[@]}" build --no-link --print-out-paths "path:$repo_dir#$config_attr.$1" 2>"$work_dir/$1.err"
}

profile=$(build home.path)
if [[ -z $profile ]]; then
  fail build-profile "$(tr '\n' ' ' <"$work_dir/home.path.err" | cut -c1-300)"
  echo "summary: $checks checks, $failures failed (host $host, repo $repo_dir)"
  exit 1
fi
ok build-profile

home_files=$(build home-files)
if [[ -z $home_files ]]; then
  fail build-home-files "$(tr '\n' ' ' <"$work_dir/home-files.err" | cut -c1-300)"
else
  ok build-home-files
fi

for cmd in "${commands[@]}"; do
  if [[ -x $profile/bin/$cmd ]]; then ok "bin-$cmd"; else fail "bin-$cmd" "$profile/bin/$cmd is not executable"; fi
done

# An empty HOME, so an already installed profile cannot stand in for the one
# just built. Ceiling: on a host whose /etc/zshenv prepends another Nix profile
# (a switched nix-darwin host), that profile answers instead and this fails.
zsh_home=$work_dir/empty-home
mkdir -p "$zsh_home"
for cmd in "${commands[@]}"; do
  got=$(env -i HOME="$zsh_home" TERM=dumb PATH="$profile/bin:/usr/bin:/bin" \
    "$zsh_bin" -c "command -v $cmd" 2>/dev/null)
  is "zsh-$cmd" "$profile/bin/$cmd" "$got"
done

if [[ -n $home_files ]]; then
  for dir in "${real_dirs[@]}"; do
    if [[ -d $home_files/$dir && ! -L $home_files/$dir ]]; then
      ok "real-dir-$dir"
    else
      fail "real-dir-$dir" "$(ls -ld "$home_files/$dir" 2>&1)"
    fi
  done
  # Two hops: the entry points at a store hm_* link, which points at the
  # checkout. The checkout exists only on the owner's machine, so follow the
  # links by name instead of asking the filesystem.
  for path in "${linked_files[@]}"; do
    target=$(readlink "$home_files/$path" 2>/dev/null)
    target=$(readlink "$target" 2>/dev/null)
    is "link-$path" "home/$path" "${target#*/dotfiles/}"
  done
fi

# The global mise config refuses an asdf tool before it resolves anything, so
# this needs no network and no plugin that exists.
mise_out=$(cd "$work_dir" && env -i HOME="$zsh_home" PATH=/usr/bin:/bin \
  MISE_CONFIG_DIR="$repo_dir/home/.config/mise" \
  MISE_DATA_DIR="$work_dir/mise-data" MISE_CACHE_DIR="$work_dir/mise-cache" \
  MISE_STATE_DIR="$work_dir/mise-state" GIT_TERMINAL_PROMPT=0 \
  "$profile/bin/mise" use 'asdf:paveg/no-such-mise-plugin@0.0.0' 2>&1)
if grep -q 'disabled by disable_backends' <<<"$mise_out"; then
  ok mise-refuses-asdf
else
  fail mise-refuses-asdf "$(tr '\n' ' ' <<<"$mise_out" | cut -c1-300)"
fi

echo "summary: $checks checks, $failures failed (host $host, repo $repo_dir)"
if ((failures > 0)); then exit 1; fi
