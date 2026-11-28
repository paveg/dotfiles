#!/usr/bin/env bash
# Break one condition of the gh wrapper at a time and require the checks in
# tests/ghtkn.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. Every check has a mutant here. The builds use Nix's own bash
# and coreutils, so the mutants run on Linux alone.
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)

# shellcheck source=tests/lib/mutate.sh
source "$repo_dir/tests/lib/mutate.sh"

copied=(flake.nix flake.lock nix home)
run_mutant() { # <dir> <check>... <file> <old> <new>
  local dir=$1 checks=$2 file=$3 old=$4 new=$5 entry out
  for entry in "${copied[@]}"; do
    cp -R "$repo_dir/$entry" "$dir/$entry"
  done
  mutate_apply "$dir/$file" "$old" "$new" || return
  out=$("$repo_dir/tests/ghtkn.sh" "$dir" 2>&1) || true
  mutate_has_summary "$out" || return
  # shellcheck disable=SC2086 # one check name per word
  mutate_checks_failed "$out" $checks
}

expect_caught() { # <check>... <description> <file> <old> <new>
  mutant "$2" run_mutant "$1" "$3" "$4" "$5"
}

mutate_inputs "${copied[@]}" tests/ghtkn.sh tests/mutate-ghtkn.sh tests/lib/
mutate_baseline 'the files as committed' "$repo_dir/tests/ghtkn.sh"

wrapper=nix/gh.sh
expect_caught 'pass-gh-token pass-gh-token-skips-ghtkn' 'the wrapper ignores GH_TOKEN' \
  "$wrapper" '-n ${GH_TOKEN-} || ' ''

expect_caught 'pass-github-token pass-github-token-skips-ghtkn' 'the wrapper ignores GITHUB_TOKEN' \
  "$wrapper" ' || -n ${GITHUB_TOKEN-}' ''

expect_caught ghtkn-args 'the wrapper hands ghtkn itself instead of the real gh' \
  "$wrapper" '-- "$gh" "$@" || status' '-- "$0" "$@" || status'

expect_caught 'ghtkn-token-reaches-gh ghtkn-args' 'the wrapper hands ghtkn a bare gh, which ghtkn looks up on PATH' \
  "$wrapper" '-- "$gh" "$@" || status' '-- gh "$@" || status'

expect_caught 'ghtkn-args app-from-xdg-config-home' 'the wrapper names no app, so ghtkn picks one' \
  "$wrapper" '-e "GH_TOKEN:$app"' '-e GH_TOKEN'

# Each mutant still has to pass the shellcheck that writeShellApplication runs,
# or the build fails before any check does.
expect_caught ghtkn-args 'the wrapper joins its arguments into one' \
  "$wrapper" '-- "$gh" "$@" || status' '-- "$gh" "$*" || status'

expect_caught no-token-unlock-hint 'the wrapper says nothing on 111' \
  "$wrapper" $'if ((status == 111)); then\n  echo' $'if ((status == 0)); then\n  echo'

expect_caught no-token-unlock-hint 'the hint leaves out --enable-refresh, so refresh tokens are dropped' \
  "$wrapper" "run 'ghtkn agent unlock --enable-refresh'" "run 'ghtkn agent unlock'"

expect_caught 'no-token-status other-status-kept' 'the wrapper turns every failure into 1' \
  "$wrapper" 'exit "$status"' 'exit $((status ? 1 : 0))'

expect_caught other-status-kept 'the hint follows every failure, not only 111' \
  "$wrapper" 'if ((status == 111)); then' 'if ((status != 0)); then'

expect_caught 'no-app-file no-app-file-skips-ghtkn empty-app-file empty-app-file-skips-ghtkn' \
  'the wrapper runs ghtkn with whatever gh-app gave, even nothing' \
  "$wrapper" $'if [[ -z $app ]]; then\n  echo "gh: $app_file names no ghtkn app" >&2\n  exit 1\nfi\n' ''

expect_caught app-from-xdg-config-home 'the wrapper reads gh-app from ~/.config whatever XDG_CONFIG_HOME says' \
  "$wrapper" 'app_file=${XDG_CONFIG_HOME:-$HOME/.config}/ghtkn/gh-app' 'app_file=$HOME/.config/ghtkn/gh-app'

mutate_finish
