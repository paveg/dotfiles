#!/usr/bin/env bash
# Break one condition of the gh wrapper, the render step or the personal
# template at a time and require the checks in tests/ghtkn.sh that cover it to
# fail. A surviving mutant means those checks prove nothing. The builds use
# Nix's own bash and coreutils, so the mutants run on Linux alone.
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
  "$wrapper" 'caller_token=${GH_TOKEN-}${GITHUB_TOKEN-}' 'caller_token=${GITHUB_TOKEN-}'

expect_caught 'pass-github-token pass-github-token-skips-ghtkn' 'the wrapper ignores GITHUB_TOKEN' \
  "$wrapper" 'caller_token=${GH_TOKEN-}${GITHUB_TOKEN-}' 'caller_token=${GH_TOKEN-}'

expect_caught 'empty-gh-token-asks-ghtkn blank-token-asks-ghtkn' 'an empty GH_TOKEN counts as a token, so gh runs with none' \
  "$wrapper" 'caller_token=${GH_TOKEN-}' 'caller_token=${GH_TOKEN+set}'

expect_caught blank-token-asks-ghtkn 'a whitespace-only token counts as a token' \
  "$wrapper" '-n ${caller_token//[[:space:]]/}' '-n $caller_token'

expect_caught 'token-free-no-argument token-free--h token-free---help token-free-help token-free---version
  token-free-version token-free-completion token-free-__complete token-free-__completeNoDesc token-free-config
  token-free-alias zsh-completes-without-token' 'what needs no token still waits for ghtkn' \
  "$wrapper" $'  exec "$gh" "$@"\n  ;;' $'  :\n  ;;'

expect_caught 'token-free-__complete zsh-completes-without-token' 'shell completion asks ghtkn, so zsh offers nothing while the agent is locked' \
  "$wrapper" ' __complete |' ''

expect_caught token-free---version 'gh --version asks ghtkn' \
  "$wrapper" ' --version |' ''

expect_caught extension-asks-ghtkn 'extensions run with no token' \
  "$wrapper" '| alias)' '| alias | extension)'

expect_caught app-without-newline 'a gh-app with no trailing newline names no app' \
  "$wrapper" 'read -r app <"$app_file" || :' 'read -r app <"$app_file" || app='

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

render=nix/ghtkn-render.sh
expect_caught 'render-signed-out render-changed-signed-out-keeps-file' 'the render writes while op is signed out' \
  "$render" $'"$op" whoami >/dev/null 2>&1 || skip "1Password is not signed in"\n' ''

expect_caught 'render-without-op render-signed-out' 'the render fails the switch where it should skip' \
  "$render" $'  echo "ghtkn-render: warning: $1, so $target is not rendered; the next switch tries again" >&2\n  exit 0' \
  $'  echo "ghtkn-render: warning: $1, so $target is not rendered; the next switch tries again" >&2\n  exit 1'

expect_caught 'render-unchanged-signed-in-calls-no-op render-unchanged-signed-out-calls-no-op' \
  'the render asks op even when nothing changed' \
  "$render" $'if [[ -f $target && $(cat "$stamp" 2>/dev/null) == "$hash" ]]; then\n  exit 0\nfi\n' ''

expect_caught render-template-changed 'the render keeps any file it finds, whatever the template says' \
  "$render" '[[ -f $target && $(cat "$stamp" 2>/dev/null) == "$hash" ]]' '[[ -f $target ]]'

expect_caught render-missing-file 'the render trusts the stored hash when the file is gone' \
  "$render" '[[ -f $target && $(cat "$stamp" 2>/dev/null) == "$hash" ]]' '[[ $(cat "$stamp" 2>/dev/null) == "$hash" ]]'

expect_caught 'render-refuses-directory render-refuses-link-to-directory' \
  'the render moves its file into a directory in the target'"'"'s place' \
  "$render" $'if [[ -e $target && ! -f $target ]]; then\n  skip "the target is not a regular file"\nfi\n' ''

expect_caught render-replaces-dangling-link 'the render refuses a dangling link it could replace' \
  "$render" '[[ -e $target && ! -f $target ]]' '[[ ( -L $target || -e $target ) && ! -f $target ]]'

# mktemp and the umask each keep the file 0600, so neither alone is a mutant of
# render-mode; the directories the render makes depend on the umask alone.
expect_caught render-umask-modes 'the render makes its directories with the caller'"'"'s umask' \
  "$render" $'umask 077\n' ''

expect_caught 'render-inject-failed-keeps-file render-signed-in' 'op inject writes over the file in place' \
  "$render" 'if ! "$op" inject <"$template" >"$tmp"; then' 'if ! "$op" inject <"$template" >"$target"; then'

expect_caught 'render-inject-failed-leaves-no-temp render-killed-by-INT render-killed-by-TERM render-killed-by-HUP' \
  'a failed or killed render leaves its temporary file behind' \
  "$render" $'trap \'[[ -z $tmp ]] || rm -f -- "$tmp"\' EXIT\n' ''

expect_caught render-retries-after-failure 'the hash moves on before inject succeeds, so a failure is never retried' \
  "$render" $'if ! "$op" inject <"$template" >"$tmp"; then\n' $'echo "$hash" >"$stamp"\nif ! "$op" inject <"$template" >"$tmp"; then\n'

expect_caught render-mkdir-failed 'a directory that cannot be made fails the switch' \
  "$render" ' || skip "the target'"'"'s directory could not be created"' ''

expect_caught render-mktemp-failed 'a temporary file that cannot be created fails the switch' \
  "$render" ' || skip "no temporary file could be created"' ''

expect_caught render-stamp-failed-warns 'a hash that cannot be stored fails the switch' \
  "$render" $' ||\n  warn "$target is rendered, but its hash could not be stored in $stamp, so the next switch renders it again"' ''

expect_caught render-replaces-stamp-link 'the hash is written through a link in its place' \
  "$render" '{ tmp=$(mktemp "$stamp.XXXXXX") && echo "$hash" >"$tmp" && mv -fT "$tmp" "$stamp"; }' '{ echo "$hash" >"$stamp"; }'

expect_caught render-stamp-failed-warns 'the hash is moved into a directory in its place' \
  "$render" 'mv -fT "$tmp" "$stamp"' 'mv -f "$tmp" "$stamp"'

expect_caught render-stamp-failed-warns 'a warning fails the switch' \
  "$render" $'  echo "ghtkn-render: warning: $1" >&2\n  exit 0' $'  echo "ghtkn-render: warning: $1" >&2\n  exit 1'

expect_caught 'render-signed-in render-template-changed' 'op gets the template as a path, which op.exe on wsl cannot open' \
  "$render" '"$op" inject <"$template" >"$tmp"' '"$op" inject --in-file "$template" >"$tmp"'

expect_caught template-client-ids-are-references 'the template holds a client ID itself' \
  home/.config/ghtkn/ghtkn.personal.yaml.tpl '"{{ op://Personal/ghtkn/client_id }}"' 'Iv23liPLACEHOLDER'

expect_caught template-agent-backend 'the template leaves ghtkn on its default keyring backend' \
  home/.config/ghtkn/ghtkn.personal.yaml.tpl $'backend:\n  type: agent\n' ''

expect_caught template-has-gh-app 'gh-app.personal names an app the template does not define' \
  home/.config/ghtkn/gh-app.personal 'paveg/write' 'paveg/read'

mutate_finish
