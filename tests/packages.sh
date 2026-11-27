#!/usr/bin/env bash
# Check what the built configuration gives a host, with no Nix switch: the
# package set is exactly the one the design names, unfree packages are admitted
# by name only, every global CLI tool is in the home-manager profile and wins
# over /usr/bin, the profile that PATH names serves that same profile, the zsh,
# mise and git directories are real directories whose files link into the
# checkout, and the global mise config refuses the asdf backend.
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
# The same set by nixpkgs attribute name, from docs/design.md "Packages", so a
# package that ships no command of its own is still accounted for. `gh` is
# absent on purpose: the wrapper takes that name, and the package would collide
# with it.
packages=(
  claude-code git ghq fzf ripgrep fd jq neovim just lazygit lefthook gitleaks
  kubectl kubernetes-helm k9s stern ghtkn mise atuin
)
# home-manager puts these in home.packages itself, so the set under test is
# not the whole list. Ceiling: a home-manager update that changes its own set
# fails package-names, and the fix is to edit this list.
hm_packages=(home-configuration-reference-manpage hm-session-vars.sh)
if [[ $host == wsl ]]; then
  hm_packages+=(dummy-xdg-mime-dirs1 dummy-xdg-mime-dirs2 man-db shared-mime-info)
fi
# Unfree packages are admitted by name. claude-code is the only one the set
# needs today; the Raycast and 1Password changes move those names here.
unfree_admitted=(claude-code)
# A prefix of an admitted name and that name with a suffix are in here, so a
# predicate that matches on anything less than the whole name is refused.
unfree_refused=(claude claude-code-x cursor raycast unrar vscode)
# One link per file, so these directories stay real directories.
linked_files=(
  .zshenv
  .config/zsh/.zshenv .config/zsh/.zprofile .config/zsh/.zshrc
  .config/mise/config.toml
  .config/git/config .config/git/ignore .config/git/personal.gitconfig
)
real_dirs=(.config/zsh .config/mise .config/git)
# <link>:<file under home/>, where the file that is linked depends on the OS.
platform=darwin
[[ $host == wsl ]] && platform=wsl
linked_files+=(".config/git/platform.gitconfig:.config/git/$platform.gitconfig")

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

brief() { # <file>
  tr '\n' ' ' <"$1" | cut -c1-300
}

sorted() { # <word>...
  local out
  out=$(printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' ')
  printf '%s' "${out% }"
}

summary() {
  echo "summary: $checks checks, $failures failed (host $host, repo $repo_dir)"
}

user=$("${nix_bin[@]}" eval --raw --file "$repo_dir/hosts/$host.nix" user 2>"$work_dir/user.err")
if [[ -z $user ]]; then
  fail host-user "hosts/$host.nix has no user: $(brief "$work_dir/user.err")"
  summary
  exit 1
fi
ok host-user

if [[ $host == wsl ]]; then
  home_dir=/home/$user
  root_attr="homeConfigurations.\"$user@wsl\""
  hm_expr=c.config
  config_attr="homeConfigurations.\"$user@wsl\".config"
else
  home_dir=/Users/$user
  root_attr="darwinConfigurations.$host"
  hm_expr="c.config.home-manager.users.\"$user\""
  config_attr="darwinConfigurations.$host.config.home-manager.users.$user"
fi
# Where every link has to point, by design.md "Repository layout". Derived from
# the host's login name rather than read back from the configuration, so a
# configuration that moves the checkout cannot agree with itself.
checkout=$home_dir/repos/github.com/paveg/dotfiles

# The nixpkgs configuration and the package list, from the pkgs set that builds
# the profile. Evaluation only, and before any build, so these answer for a
# host whose system this machine cannot build.
facts_fn=$(
  cat <<NIX
c:
let
  pkgs = c.pkgs;
  cfg = pkgs.config;
  lib = pkgs.lib;
  # What nixpkgs asks before it evaluates an unfree package, with a name in
  # place of the package: allowUnfree lets every one of them through.
  admits = name: cfg.allowUnfree || (cfg.allowUnfreePredicate or (_: false)) { pname = name; version = "0"; };
  words = xs: lib.concatStringsSep " " (lib.sort (a: b: a < b) xs);
in
lib.concatStrings [
  "allow-unfree " (lib.boolToString cfg.allowUnfree) "\n"
  "unfree-admitted " (words (builtins.filter admits [ $(printf '"%s" ' "${unfree_admitted[@]}" "${unfree_refused[@]}") ])) "\n"
  "packages " (words (map (p: lib.getName p) $hm_expr.home.packages))
]
NIX
)
fact() { # <key>
  local line
  line=$(grep "^$1 " <<<"$facts")
  printf '%s' "${line#"$1" }"
}

facts=$("${nix_bin[@]}" eval --raw "path:$repo_dir#$root_attr" --apply "$facts_fn" 2>"$work_dir/facts.err")
if [[ -z $facts ]]; then
  fail profile-facts "$(brief "$work_dir/facts.err")"
else
  ok profile-facts
  is unfree-allow-unfree false "$(fact allow-unfree)"
  is unfree-admitted "$(sorted "${unfree_admitted[@]}")" "$(fact unfree-admitted)"
  is package-names "$(sorted "${packages[@]}" "${hm_packages[@]}")" "$(fact packages)"
fi

# path: rather than the directory on its own, so a copied or uncommitted tree
# builds the same way a checkout does.
build_attr() { # <attribute> <log-name>
  "${nix_bin[@]}" build --no-link --print-out-paths "path:$repo_dir#$1" 2>"$work_dir/$2.err"
}

profile=$(build_attr "$config_attr.home.path" profile)
if [[ -z $profile ]]; then
  fail build-profile "$(brief "$work_dir/profile.err")"
  summary
  exit 1
fi
ok build-profile

home_files=$(build_attr "$config_attr.home-files" home-files)
if [[ -z $home_files ]]; then
  fail build-home-files "$(brief "$work_dir/home-files.err")"
else
  ok build-home-files
fi

for cmd in "${commands[@]}"; do
  if [[ -x $profile/bin/$cmd ]]; then
    ok "bin-$cmd"
  else
    fail "bin-$cmd" "$profile/bin/$cmd is not executable"
  fi
done

# An empty HOME, so an already installed profile cannot stand in for the one
# just built. Ceiling: on a host whose /etc/zshenv prepends another Nix profile
# (a switched nix-darwin host), that profile answers instead and this fails.
zsh_home=$work_dir/empty-home
mkdir -p "$zsh_home"
for cmd in "${commands[@]}"; do
  got=$(env -i HOME="$zsh_home" TERM=dumb PATH="$profile/bin:/usr/bin:/bin" \
    "$zsh_bin" -c "command -v $cmd" 2>"$work_dir/zsh.err")
  if [[ $got == "$profile/bin/$cmd" ]]; then
    ok "zsh-$cmd"
  else
    fail "zsh-$cmd" "want '$profile/bin/$cmd', got '$got', stderr: $(brief "$work_dir/zsh.err")"
  fi
done

# PATH names a profile, not home.path itself: on macOS the per-user profile
# nix-darwin builds, on wsl the one home-manager's generation installs.
if [[ $host == wsl ]]; then
  generation=$(build_attr "homeConfigurations.\"$user@wsl\".activationPackage" generation)
  if [[ -z $generation ]]; then
    fail build-generation "$(brief "$work_dir/generation.err")"
  else
    is generation-home-path "$profile" "$(readlink "$generation/home-path" 2>"$work_dir/readlink.err")"
  fi
else
  system=$(build_attr "darwinConfigurations.$host.system" system)
  if [[ -z $system ]]; then
    fail build-system "$(brief "$work_dir/system.err")"
  else
    for cmd in "${commands[@]}"; do
      per_user=$system/etc/profiles/per-user/$user/bin/$cmd
      is "per-user-$cmd" "$profile/bin/$cmd" "$(readlink "$per_user" 2>>"$work_dir/readlink.err")"
    done
  fi
fi

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
  # links by name instead of asking the filesystem. A file copied into the
  # store has no second hop, and the store path is what fails the comparison.
  for entry in "${linked_files[@]}"; do
    path=${entry%%:*} source=${entry#*:}
    store_link=$(readlink "$home_files/$path" 2>>"$work_dir/readlink.err")
    target=$(readlink "$store_link" 2>>"$work_dir/readlink.err") || target=$store_link
    is "link-$path" "$checkout/home/$source" "$target"
  done
  if [[ -s $work_dir/readlink.err && $failures -gt 0 ]]; then
    echo "readlink stderr: $(brief "$work_dir/readlink.err")"
  fi
fi

# The global mise config refuses an asdf tool before it resolves anything, so
# this needs no network and no plugin that exists.
run_mise() { # <argument>...
  (cd "$work_dir" && env -i HOME="$zsh_home" PATH=/usr/bin:/bin \
    MISE_CONFIG_DIR="$repo_dir/home/.config/mise" \
    MISE_DATA_DIR="$work_dir/mise-data" MISE_CACHE_DIR="$work_dir/mise-cache" \
    MISE_STATE_DIR="$work_dir/mise-state" GIT_TERMINAL_PROMPT=0 \
    "$profile/bin/mise" "$@" 2>&1)
}

mise_out=$(run_mise use 'asdf:paveg/no-such-mise-plugin@0.0.0')
if grep -q 'disabled by disable_backends' <<<"$mise_out"; then
  ok mise-refuses-asdf
else
  fail mise-refuses-asdf "$(tr '\n' ' ' <<<"$mise_out" | cut -c1-300)"
fi
# asdf and nothing else: disabling a backend a project needs would be refused
# the same way, and the message above does not say which backend is off.
is mise-disable-backends '["asdf"]' "$(run_mise settings get disable_backends)"

summary
if ((failures > 0)); then exit 1; fi
