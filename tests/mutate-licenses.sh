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

# shellcheck source=tests/lib/mutate.sh
source "$repo_dir/tests/lib/mutate.sh"

# Fill <dir> with a copy of the files under test and apply each edit to it.
apply_edits() { # <dir> <file> <old> <new> [<file> <old> <new>]...
  local dir=$1 entry
  shift
  for entry in flake.nix flake.lock hosts nix home docs; do
    cp -R "$repo_dir/$entry" "$dir/$entry" || return
  done
  while (($# >= 3)); do
    mutate_apply "$dir/$1" "$2" "$3" || return
    shift 3
  done
}

run_clean() { # <dir> <row> <file> <old> <new> [<file> <old> <new>]...
  local dir=$1 row=$2 out
  shift 2
  apply_edits "$dir" "$@" || return
  if out=$("$repo_dir/tests/licenses.sh" "$dir" 2>&1) && grep -Eq "$row" <<<"$out"; then
    return 0
  fi
  echo "expected a pass with a row matching '$row'"
  grep -E '^(FAIL|summary)' <<<"$out" | head -5
  return 1
}

run_caught() { # <dir> <check>... <file> <old> <new> [<file> <old> <new>]...
  local dir=$1 checks=$2 out check wrong
  shift 2
  apply_edits "$dir" "$@" || return
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
  [[ -z $wrong ]] && return 0
  echo "wrong:$wrong"
  grep -E '^(FAIL|summary)' <<<"$out" | head -5
  return 1
}

# A mutant that must still pass, with <row> (a regular expression) in its table.
expect_clean() { # <row> <description> <file> <old> <new> [<file> <old> <new>]...
  clean_mutant "$2" run_clean "$1" "${@:3}"
}

expect_caught() { # <check>... <description> <file> <old> <new> [<file> <old> <new>]...
  mutant "$2" run_caught "$1" "${@:3}"
}

h=$host
last_package=$'    atuin\n  ]'
with_package() { # <expression>
  printf '    atuin\n    %s\n  ]' "$1"
}

mutate_baseline 'the files as committed' "$repo_dir/tests/licenses.sh"

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

expect_caught "unfree-$h-unrar" \
  'flake.nix allows every unfree package, not by name, and an unfree one is installed' \
  nix/packages.nix "$last_package" "$(with_package unrar)" \
  flake.nix '      nixpkgsConfig = {' $'      nixpkgsConfig = {\n        allowUnfree = true;'

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

expect_caught "non-commercial-$h-jq !unfree-$h-jq" \
  'a licence says non-commercial only in its full name, allowed by name' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.inria-compcert; }; }))\n' \
  flake.nix '[ "claude-code" ]' '[ "claude-code" "jq" ]'

expect_caught "non-commercial-$h-jq !unfree-$h-jq !non-redistributable-$h-jq" \
  'a hand-written free licence says non-commercial only in its full name' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = { shortName = "example"; fullName = "Example Non-Commercial License"; free = true; redistributable = true; }; }; }))\n'

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

expect_caught "non-commercial-$h-jq !unfree-$h-jq" \
  'a licence is the bare string CC-BY-NC-4.0, allowed by name' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = "CC-BY-NC-4.0"; }; }))\n' \
  flake.nix '[ "claude-code" ]' '[ "claude-code" "jq" ]'

expect_caught "non-commercial-$h-jq !unfree-$h-jq" \
  'a licence has NC in its short name only, allowed by name' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.ocamlpro_nc; }; }))\n' \
  flake.nix '[ "claude-code" ]' '[ "claude-code" "jq" ]'

expect_caught "unfree-$h-jq non-redistributable-$h-jq" \
  'a WITH licence has an unfree base' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.WITH lib.licenses.unfree lib.licenses.classpathException20; }; }))\n'

expect_caught "non-commercial-$h-jq !unfree-$h-jq" \
  'a WITH licence has a non-commercial base, allowed by name' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.WITH lib.licenses.cc-by-nc-40 lib.licenses.classpathException20; }; }))\n' \
  flake.nix '[ "claude-code" ]' '[ "claude-code" "jq" ]'

expect_caught "non-commercial-$h-jq unfree-$h-jq non-redistributable-$h-jq" \
  'a PLUS licence has a non-commercial base' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.PLUS lib.licenses.cc-by-nc-40; }; }))\n'

expect_caught "unfree-$h-jq non-redistributable-$h-jq" \
  'a hand-written licence says neither whether it is free nor redistributable' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = { spdxId = "LicenseRef-custom"; }; }; }))\n'

expect_caught "unfree-$h-jq non-redistributable-$h-jq" \
  'a WITH licence has an unfree exception' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = lib.licenses.WITH lib.licenses.mit lib.licenses.unfree; }; }))\n'

expect_caught "unfree-$h-jq non-redistributable-$h-jq" \
  'a compound licence has an operator the check does not know' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = { licenseType = "compound"; operator = "XOR"; licenses = [ lib.licenses.unfree ]; }; }; }))\n'

expect_caught "non-commercial-$h-jq !unfree-$h-jq" \
  'a free licence has NC in its SPDX id only' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = { spdxId = "CC-BY-NC-4.0"; shortName = "custom"; free = true; redistributable = true; }; }; }))\n'

expect_caught "non-commercial-$h-jq !unfree-$h-jq" \
  'a free licence spells noncommercial without a hyphen in its full name' \
  nix/packages.nix $'    jq\n' \
  $'    (jq.overrideAttrs (old: { meta = old.meta // { license = { shortName = "example"; fullName = "Example Noncommercial License"; free = true; redistributable = true; }; }; }))\n'

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

  expect_caught 'no-entry-wsl-Example.Gap' \
    'design.md gains a winget install with two spaces between winget and install' \
    docs/design.md "$onepassword_line" \
    "$(printf '%s\n  - Example: `winget  install --id Example.Gap -e`.' "$onepassword_line")"

  expect_caught 'no-entry-wsl-Example.Store' \
    'design.md gains a winget install whose id follows -s and its value' \
    docs/design.md "$onepassword_line" "$(with_winget '-s msstore Example.Store')"

  expect_caught 'unparsed-wsl---bogus_Example.Tool' \
    'design.md gains a winget install with an option the check does not know' \
    docs/design.md "$onepassword_line" "$(with_winget '--bogus Example.Tool')"

  expect_caught 'unparsed-wsl-Example.One_Example.Two' \
    'design.md gains a winget install that names two packages' \
    docs/design.md "$onepassword_line" "$(with_winget 'Example.One Example.Two')"

  expect_caught 'no-entry-wsl-raycast' \
    'a winget install without --id has no entry' \
    nix/licenses.nix $'      raycast = unfree;\n' ''

  expect_caught 'non-commercial-wsl-StablyAI.Orca' \
    'an install from outside Nix is recorded with a non-commercial licence' \
    nix/licenses.nix '"StablyAI.Orca" = mit;' '"StablyAI.Orca" = cc-by-nc-40;'

  expect_caught 'non-commercial-wsl-udev-gothic-nf' \
    'an install kept by hand is recorded with a non-commercial licence' \
    nix/licenses.nix 'udev-gothic-nf = ofl;' 'udev-gothic-nf = cc-by-nc-40;'
else
  mutate_na "the winget mutants need wsl, and this run is on $host"
fi

if [[ $host != wsl ]]; then
  expect_caught "no-entry-$h-karabiner-elements" \
    'a Homebrew cask has no entry in nix/licenses.nix' \
    nix/darwin.nix $'  nix.enable = false;\n' $'  nix.enable = false;\n  homebrew.casks = [ "karabiner-elements" ];\n'

  expect_caught "no-entry-$h-jq" \
    'a Homebrew formula has no entry in nix/licenses.nix' \
    nix/darwin.nix $'  nix.enable = false;\n' $'  nix.enable = false;\n  homebrew.brews = [ "jq" ];\n'

  expect_caught "unread-$h-extraConfig" \
    'a Homebrew cask is given through homebrew.extraConfig, which the check does not read' \
    nix/darwin.nix $'  nix.enable = false;\n' \
    $'  nix.enable = false;\n  homebrew.extraConfig = \'\'\n    cask "karabiner-elements"\n  \'\';\n'

  expect_caught "unfree-$h-unrar" \
    'an unfree system package that is not allowed by name' \
    nix/darwin.nix $'  nix.enable = false;\n' $'  nix.enable = false;\n  environment.systemPackages = [ pkgs.unrar ];\n'

  expect_caught "unfree-$h-corefonts" \
    'an unfree font that is not allowed by name' \
    nix/darwin.nix $'  nix.enable = false;\n' $'  nix.enable = false;\n  fonts.packages = [ pkgs.corefonts ];\n'

  expect_caught "no-licence-$h-darwin-rebuild" \
    'a nix-darwin derivation loses its recorded licence' \
    nix/licenses.nix $'    "darwin-rebuild" = mit;\n' ''
else
  mutate_na "the system, font, and Homebrew mutants need a macOS host, and this run is on $host"
fi

mutate_context="host $host"
mutate_finish
