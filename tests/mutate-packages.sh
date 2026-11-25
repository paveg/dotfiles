#!/usr/bin/env bash
# Break one condition of the package wiring at a time and require the checks in
# tests/packages.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. Every check has a mutant here except host-user and
# build-home-files, which guard this harness rather than the files under test.
# Env: DOTFILES_HOST and ZSH_BIN are passed through to tests/packages.sh.
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0

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
  local checks=$1 description=$2 file=$3 old=$4 new=$5 dir out check missing
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
    echo "caught: $description"
  else
    echo "MISSED: $description (expected to fail:$missing)"
    grep -E '^(FAIL|summary)' <<<"$out" | head -5
    failures=$((failures + 1))
  fi
}

expect_pass

expect_caught 'bin-rg zsh-rg' 'a package is dropped from the list' \
  nix/packages.nix $'    ripgrep\n' ''

expect_caught 'bin-claude zsh-claude' 'Claude Code is dropped from the list' \
  nix/packages.nix $'    claude-code\n' ''

expect_caught build-profile 'the unfree allowance no longer names claude-code' \
  flake.nix '[ "claude-code" ]' '[ ]'

expect_caught 'real-dir-.config/zsh' 'the zsh directory is linked as a whole' \
  nix/home.nix $'  xdg.configFile = lib.genAttrs [ "zsh/.zshenv" "zsh/.zprofile" "zsh/.zshrc" "mise/config.toml" ] (path: {\n    source = link ".config/${path}";\n  });\n' \
  $'  xdg.configFile."zsh".source = link ".config/zsh";\n'

expect_caught mise-refuses-asdf 'the global mise config allows the asdf backend' \
  home/.config/mise/config.toml 'disable_backends = ["asdf"]' 'disable_backends = []'

if ((failures > 0)); then
  echo "$failures mutation check(s) failed"
  exit 1
fi
echo "every mutant is caught"
