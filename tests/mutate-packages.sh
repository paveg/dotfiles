#!/usr/bin/env bash
# Break one condition of the package wiring at a time and require the checks in
# tests/packages.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. The per-tool checks are mutated through `git` (which /usr/bin
# also has) and `claude` (which it does not). These checks have no mutant:
# host-user, profile-facts, build-home-files, build-system and build-generation
# guard this harness rather than the files under test, and generation-home-path
# is home-manager's own link to the profile this test already built.
# The per-user group reads the built macOS system, so it needs a mac; CI runs
# it in the darwin jobs and the common group on the Linux runner.
# Usage: tests/mutate-packages.sh [group]
#        group: all (default), common, per-user
# Env: DOTFILES_HOST and ZSH_BIN are passed through to tests/packages.sh.
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
group=${1:-all}
default_host=wsl
[[ $(uname -s) == Darwin ]] && default_host=personal-mac
host=${DOTFILES_HOST:-$default_host}

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

caught=0
skipped=0
failures=0

runs() { # <group>
  [[ $group == all || $group == "$1" ]]
}

skip() { # <reason>
  skipped=$((skipped + 1))
  echo "n/a: $1"
}

expect_pass() {
  local out
  if out=$("$repo_dir/tests/packages.sh" 2>&1); then
    echo "pass: the files as committed"
  else
    echo "FAIL: the files as committed should pass"
    grep '^FAIL' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

expect_caught() { # <check>... <description> <file> <old> <new>
  local checks=$1 description=$2 file=$3 old=$4 new=$5 dir out check missing entry
  dir=$(mktemp -d "$work_dir/mutant.XXXX")
  for entry in flake.nix flake.lock hosts nix home; do
    cp -R "$repo_dir/$entry" "$dir/$entry"
  done
  OLD=$old NEW=$new python3 - "$dir/$file" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
  out=$("$repo_dir/tests/packages.sh" "$dir" 2>&1) || true
  missing=
  for check in $checks; do
    grep -q "^FAIL: $check:" <<<"$out" || missing="$missing $check"
  done
  if [[ -z $missing ]]; then
    caught=$((caught + 1))
    echo "caught: $description"
  else
    echo "MISSED: $description (expected to fail:$missing)"
    grep -E '^(FAIL|summary)' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

expect_pass

if runs common; then
  # git is the case that matters most: /usr/bin has one, so a dropped package is
  # answered by the system copy rather than by "not found".
  expect_caught 'bin-git zsh-git package-names' 'git is dropped from the list' \
    nix/packages.nix $'    git\n' ''

  expect_caught 'bin-claude zsh-claude package-names' 'Claude Code is dropped from the list' \
    nix/packages.nix $'    claude-code\n' ''

  expect_caught 'package-names' 'the real gh is added, which the wrapper needs the name of' \
    nix/packages.nix $'    atuin\n  ];\n' $'    atuin\n    gh\n  ];\n'

  expect_caught 'package-names' 'a language runtime is installed globally' \
    nix/packages.nix $'    atuin\n  ];\n' $'    atuin\n    nodejs\n  ];\n'

  expect_caught 'unfree-admitted build-profile' 'the unfree allowance no longer names claude-code' \
    flake.nix '[ "claude-code" ]' '[ ]'

  expect_caught 'unfree-allow-unfree unfree-admitted' 'every unfree package is allowed' \
    flake.nix 'allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ];' \
    'allowUnfree = true;'

  expect_caught 'unfree-admitted' 'the unfree predicate admits a second name' \
    flake.nix '[ "claude-code" ]' '[ "claude-code" "unrar" ]'

  expect_caught 'unfree-admitted' 'the unfree predicate admits anything it is asked about' \
    flake.nix 'pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ]' 'pkg: true'

  expect_caught 'unfree-admitted' 'the unfree predicate matches a prefix of the name' \
    flake.nix 'builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ]' \
    'nixpkgs.lib.hasPrefix "claude-code" (nixpkgs.lib.getName pkg)'

  expect_caught 'real-dir-.config/zsh' 'the zsh directory is linked as a whole' \
    nix/home.nix $'      "zsh/.zshenv"\n      "zsh/.zprofile"\n      "zsh/.zshrc"\n' $'      "zsh"\n'

  expect_caught 'real-dir-.config/mise' 'the mise directory is linked as a whole' \
    nix/home.nix '"mise/config.toml"' '"mise"'

  # The platform file goes too: a link inside a linked directory fails the build.
  expect_caught 'real-dir-.config/git' 'the git directory is linked as a whole' \
    nix/home.nix \
    $'      "git/config"\n      "git/ignore"\n      "git/personal.gitconfig"\n    ] (path: {\n      source = link ".config/${path}";\n    })\n    // {\n      # The 1Password signer, and on wsl the ssh command, under the one name the git config includes.\n      "git/platform.gitconfig".source = link ".config/git/${platform}.gitconfig";\n    };\n' \
    $'      "git"\n    ] (path: {\n      source = link ".config/${path}";\n    });\n'

  expect_caught 'link-.config/git/personal.gitconfig' 'the personal identity is not linked' \
    nix/home.nix $'      "git/personal.gitconfig"\n' ''

  expect_caught 'link-.config/git/platform.gitconfig' 'the other OS'"'"'s signer is linked' \
    nix/home.nix 'then "darwin" else "wsl"' 'then "wsl" else "darwin"'

  expect_caught 'link-.config/zsh/.zshrc link-.config/mise/config.toml link-.config/git/config' \
    'the files are copied into the store instead of linked out of it' \
    nix/home.nix '    source = link ".config/${path}";' '    source = ../home/.config/${path};'

  expect_caught 'link-.zshenv link-.config/zsh/.zshrc' 'the links point at a checkout somewhere else' \
    nix/home.nix '"${config.home.homeDirectory}/repos/github.com/paveg/dotfiles"' '"/tmp/elsewhere/dotfiles"'

  expect_caught 'link-.zshenv' 'the top-level .zshenv is not linked at all' \
    nix/home.nix $'  home.file.".zshenv".source = link ".zshenv";\n' ''

  expect_caught 'link-.zshenv' 'the top-level .zshenv is copied into the store' \
    nix/home.nix 'link ".zshenv"' '../home/.zshenv'

  expect_caught 'mise-refuses-asdf mise-disable-backends' 'the global mise config allows the asdf backend' \
    home/.config/mise/config.toml 'disable_backends = ["asdf"]' 'disable_backends = []'

  expect_caught 'mise-disable-backends' 'the global mise config disables a backend the projects use' \
    home/.config/mise/config.toml 'disable_backends = ["asdf"]' 'disable_backends = ["asdf", "aqua"]'
fi

if runs per-user; then
  if [[ $host == wsl ]]; then
    skip "the per-user profile checks need a macOS host, and this run is on $host"
  else
    expect_caught 'per-user-git per-user-claude' 'the packages never reach the per-user profile' \
      nix/darwin.nix $'    useUserPackages = true;\n' ''
  fi
fi

if ((failures > 0)); then
  echo "$failures mutation check(s) failed"
  exit 1
fi
if ((caught == 0)); then
  echo "no mutant ran (group $group, host $host)"
  exit 1
fi
echo "every mutant is caught ($caught caught, $skipped n/a, group $group, host $host)"
