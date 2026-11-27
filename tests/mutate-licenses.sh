#!/usr/bin/env bash
# Break one condition of the licence check's subject at a time and require the
# checks in tests/licenses.sh that cover it to fail, and the ones named with a
# leading `!` not to. A surviving mutant means those checks prove nothing. The
# `evaluate` check has no mutant: it guards this harness. The winget mutants
# need wsl, whose Windows side design.md describes, and the system, font, and
# Homebrew ones need a macOS host; each runs where its host is evaluated.
# Usage: tests/mutate-licenses.sh
# Env: DOTFILES_HOST is passed through to tests/licenses.sh.
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
default_host=wsl
[[ $(uname -s) == Darwin ]] && default_host=personal-mac
host=${DOTFILES_HOST:-$default_host}
export DOTFILES_HOST=$host

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

caught=0
clean=0
skipped=0
failures=0

skip() { # <reason>
  skipped=$((skipped + 1))
  echo "n/a: $1"
}

# A copy of the files under test with each <file> <old> <new> edit applied.
mutant() { # <file> <old> <new> [<file> <old> <new>]...
  local dir entry
  dir=$(mktemp -d "$work_dir/mutant.XXXX")
  for entry in flake.nix flake.lock hosts nix home docs; do
    cp -R "$repo_dir/$entry" "$dir/$entry"
  done
  while (($# >= 3)); do
    OLD=$2 NEW=$3 python3 - "$dir/$1" <<'PY' || return 1
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if text.count(old) != 1:
    sys.exit(f"mutation target found {text.count(old)} times: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
    shift 3
  done
  echo "$dir"
}

expect_pass() {
  local out
  if out=$("$repo_dir/tests/licenses.sh" 2>&1); then
    echo "pass: the files as committed"
  else
    echo "FAIL: the files as committed should pass"
    grep '^FAIL' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

# A mutant that must still pass, with <row> (a regular expression) in its table.
expect_clean() { # <row> <description> <file> <old> <new> [<file> <old> <new>]...
  local row=$1 description=$2 dir out
  shift 2
  dir=$(mutant "$@") || {
    failures=$((failures + 1))
    return
  }
  if out=$("$repo_dir/tests/licenses.sh" "$dir" 2>&1) && grep -Eq "$row" <<<"$out"; then
    clean=$((clean + 1))
    echo "clean: $description"
  else
    echo "MISSED: $description (expected a pass with a row matching '$row')"
    grep -E '^(FAIL|summary)' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

expect_caught() { # <check>... <description> <file> <old> <new> [<file> <old> <new>]...
  local checks=$1 description=$2 dir out check wrong
  shift 2
  dir=$(mutant "$@") || {
    failures=$((failures + 1))
    return
  }
  out=$("$repo_dir/tests/licenses.sh" "$dir" 2>&1) && wrong=' (exit 0)' || wrong=
  # The summary line proves the run reached the end: a crash that skips later
  # rows is a broken harness, not a caught mutant.
  grep -q '^summary:' <<<"$out" || wrong="$wrong (no summary line)"
  for check in $checks; do
    if [[ $check == !* ]]; then
      ! grep -q "^FAIL: ${check#!}:" <<<"$out" || wrong="$wrong $check"
    else
      grep -q "^FAIL: $check:" <<<"$out" || wrong="$wrong $check"
    fi
  done
  if [[ -z $wrong ]]; then
    caught=$((caught + 1))
    echo "caught: $description"
  else
    echo "MISSED: $description (wrong:$wrong)"
    grep -E '^(FAIL|summary)' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

h=$host
last_package=$'    atuin\n  ];'
with_package() { # <expression>
  printf '    atuin\n    %s\n  ];' "$1"
}

expect_pass

expect_caught "non-commercial-$h-zsh-abbr unfree-$h-zsh-abbr" \
  'zsh-abbr (CC-BY-NC-SA-4.0) is installed' \
  nix/packages.nix "$last_package" "$(with_package zsh-abbr)"

expect_caught "non-commercial-$h-zsh-abbr !unfree-$h-zsh-abbr !non-redistributable-$h-zsh-abbr" \
  'zsh-abbr is installed and allowed by name' \
  nix/packages.nix "$last_package" "$(with_package zsh-abbr)" \
  flake.nix '[ "claude-code" ]' '[ "claude-code" "zsh-abbr" ]'

expect_caught "unfree-$h-unrar !non-redistributable-$h-unrar" \
  'an unfree package that is not allowed by name is installed' \
  nix/packages.nix "$last_package" "$(with_package unrar)"

expect_caught "non-redistributable-$h-jq !unfree-$h-jq" \
  'a package has a free licence that does not allow redistribution' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.mit // { redistributable = false; }; }; }))\n'

expect_caught "unfree-$h-claude-code non-redistributable-$h-claude-code" \
  'the unfree allowance in flake.nix no longer names claude-code' \
  flake.nix '[ "claude-code" ]' '[ ]'

expect_caught "non-commercial-$h-jq !unfree-$h-jq" \
  'a compound OR licence has a non-commercial alternative' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.OR [ lib.licenses.mit lib.licenses.cc-by-nc-40 ]; }; }))\n'

expect_caught "unfree-$h-jq !non-redistributable-$h-jq" \
  'a compound AND licence has an unfree part' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.AND [ lib.licenses.mit lib.licenses.unfreeRedistributable ]; }; }))\n'

expect_caught "non-commercial-$h-jq unfree-$h-jq" \
  'a licence list has a non-commercial entry' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = [ lib.licenses.mit lib.licenses.cc-by-nc-40 ]; }; }))\n'

expect_caught "unfree-$h-jq non-redistributable-$h-jq" \
  'a licence is a bare string, so whether it is free is unknown' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = "MIT"; }; }))\n'

expect_caught "unfree-$h-jq non-redistributable-$h-jq" \
  'a hand-written licence says neither whether it is free nor redistributable' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = { spdxId = "LicenseRef-custom"; }; }; }))\n'

expect_caught "no-licence-$h-jq" \
  'a package has no meta.license' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = removeAttrs old.meta [ "license" ]; }))\n'

expect_caught "no-licence-$h-jq" \
  'a package has an empty licence list' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = [ ]; }; }))\n'

expect_caught "no-licence-$h-jq" \
  'a package has a compound AND of no licences' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.AND [ ]; }; }))\n'

expect_caught "no-licence-$h-hm-session-vars.sh" \
  'a generated derivation loses its recorded licence' \
  nix/licenses.nix $'    "hm-session-vars.sh" = mit;\n' ''

expect_clean '^home +bat +\(Apache-2\.0 OR MIT\) +ok$' \
  'bat, whose licence is a compound OR of two free licences, is installed' \
  nix/packages.nix "$last_package" "$(with_package bat)"

expect_clean '^home +jq +NCSA +ok$' \
  'a package under NCSA, a free licence whose id starts with NC' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.ncsa; }; }))\n'

if [[ $host == wsl ]]; then
  expect_caught 'no-entry-wsl-StablyAI.Orca' \
    'a winget install in design.md has no entry in nix/licenses.nix' \
    nix/licenses.nix $'      "StablyAI.Orca" = mit;\n' ''

  expect_caught 'no-entry-wsl-Example.Tool' \
    'design.md gains a winget install with no entry' \
    docs/design.md '  - 1Password: `winget install --id AgileBits.1Password -e`.' \
    $'  - 1Password: `winget install --id AgileBits.1Password -e`.\n  - Example: `winget install --id Example.Tool -e`.'

  onepassword_line='  - 1Password: `winget install --id AgileBits.1Password -e`.'
  with_winget() { # <arguments>
    printf '%s\n  - Example: `winget install %s`.' "$onepassword_line" "$1"
  }
  expect_caught 'no-entry-wsl-Example.Exact' \
    'design.md gains a winget install with -e before --id' \
    docs/design.md "$onepassword_line" "$(with_winget '-e --id Example.Exact')"

  expect_caught 'no-entry-wsl-Example.ExactLong' \
    'design.md gains a winget install with --exact before --id' \
    docs/design.md "$onepassword_line" "$(with_winget '--exact --id Example.ExactLong')"

  expect_caught 'no-entry-wsl-Example.Equals' \
    'design.md gains a winget install with --id=' \
    docs/design.md "$onepassword_line" "$(with_winget '--id=Example.Equals')"

  expect_caught 'no-entry-wsl-Example.Spaced' \
    'design.md gains a winget install with two spaces before --id' \
    docs/design.md "$onepassword_line" "$(with_winget ' --id Example.Spaced -e')"

  expect_caught 'no-entry-wsl-Example.Store' \
    'design.md gains a winget install whose id follows -s and its value' \
    docs/design.md "$onepassword_line" "$(with_winget '-s msstore Example.Store')"

  expect_caught 'unparsed-wsl---bogus_Example.Tool' \
    'design.md gains a winget install with an option the check does not know' \
    docs/design.md "$onepassword_line" "$(with_winget '--bogus Example.Tool')"

  expect_caught 'no-entry-wsl-raycast' \
    'a winget install without --id has no entry' \
    nix/licenses.nix $'      raycast = unfree;\n' ''

  expect_caught 'non-commercial-wsl-StablyAI.Orca' \
    'an install from outside Nix is recorded with a non-commercial licence' \
    nix/licenses.nix '"StablyAI.Orca" = mit;' '"StablyAI.Orca" = cc-by-nc-40;'
else
  skip "the winget mutants need wsl, and this run is on $host"
fi

if [[ $host != wsl ]]; then
  expect_caught "no-entry-$h-karabiner-elements" \
    'a Homebrew cask has no entry in nix/licenses.nix' \
    nix/darwin.nix $'  nix.enable = false;\n' $'  nix.enable = false;\n  homebrew.casks = [ "karabiner-elements" ];\n'

  expect_caught "no-entry-$h-jq" \
    'a Homebrew formula has no entry in nix/licenses.nix' \
    nix/darwin.nix $'  nix.enable = false;\n' $'  nix.enable = false;\n  homebrew.brews = [ "jq" ];\n'

  expect_caught "unfree-$h-unrar" \
    'an unfree system package that is not allowed by name' \
    nix/darwin.nix '{ host, ... }:' '{ host, pkgs, ... }:' \
    nix/darwin.nix $'  nix.enable = false;\n' $'  nix.enable = false;\n  environment.systemPackages = [ pkgs.unrar ];\n'

  expect_caught "unfree-$h-corefonts" \
    'an unfree font that is not allowed by name' \
    nix/darwin.nix '{ host, ... }:' '{ host, pkgs, ... }:' \
    nix/darwin.nix $'  nix.enable = false;\n' $'  nix.enable = false;\n  fonts.packages = [ pkgs.corefonts ];\n'

  expect_caught "no-licence-$h-darwin-rebuild" \
    'a nix-darwin derivation loses its recorded licence' \
    nix/licenses.nix $'    "darwin-rebuild" = mit;\n' ''
else
  skip "the system, font, and Homebrew mutants need a macOS host, and this run is on $host"
fi

if ((failures > 0)); then
  echo "$failures mutation check(s) failed"
  exit 1
fi
echo "every mutant is caught ($caught caught, $clean clean, $skipped n/a, host $host)"
