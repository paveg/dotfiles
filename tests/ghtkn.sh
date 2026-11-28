#!/usr/bin/env bash
# Check the gh wrapper and the ghtkn.yaml render step that nix/ghtkn.nix
# builds (docs/adr/0004-github-auth-ghtkn.md), with no Nix switch, no real
# ghtkn and no real op: each run is `env -i` with a throwaway HOME and stubs
# first on PATH. The stub ghtkn records its arguments and runs the command it
# is handed with a fake token, and the real gh answers `gh auth token` with
# whatever token reached it. With a non-blank GH_TOKEN or GITHUB_TOKEN, and for
# what gh runs without a token (help, the version, completion, config, alias),
# the wrapper runs the real gh directly, which zsh's _gh then completes with;
# otherwise it asks ghtkn for the app that
# ~/.config/ghtkn/gh-app names, hands it the real gh rather than itself with
# every argument intact, keeps the exit status, says how to unlock the agent on
# 111, and refuses to run without an app. The render step writes the file
# (0600) only when it is missing or its template changed and op is signed in,
# never calls op otherwise, and skips with a warning and exit 0 when op is
# missing, signed out, or fails, keeping the old file, and when the target is
# a directory or a link to one. The committed template
# holds references, not client IDs, and defines the app gh-app.personal names.
# tests/packages.sh checks that the profile installs this same wrapper and
# that the switch runs this same render step.
# Usage: tests/ghtkn.sh [repo-dir]   (default: this checkout)
set -uo pipefail

harness_dir=$(cd "$(dirname "$0")/.." && pwd)
# Physical path: a `path:` flake reference rejects one that crosses a symlink.
repo_dir=$(cd "${1:-$harness_dir}" && pwd -P)
nix_bin=(nix --extra-experimental-features 'nix-command flakes')

work_dir=$(cd "$(mktemp -d)" && pwd -P)
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

# A broken build is an error in the harness, not a failed check.
die() { # <message>
  echo "ERROR: $1" >&2
  exit 2
}

build() { # <installable>...
  "${nix_bin[@]}" build --no-link --print-out-paths "$@" 2>"$work_dir/build.err" | tail -n 1
}

wrapper=$(build "path:$repo_dir#gh")/bin/gh
[[ -x $wrapper ]] || die "the gh wrapper did not build: $(tail -n 5 "$work_dir/build.err")"
# The gh the wrapper must hand ghtkn: nixpkgs' own, from the flake's lock.
real_gh=$(build --inputs-from "path:$repo_dir" nixpkgs#gh)/bin/gh
[[ -x $real_gh ]] || die "nixpkgs' gh did not build: $(tail -n 5 "$work_dir/build.err")"

# The stub logs one argument per line. With STUB_GHTKN_EXIT set it exits with
# that status, as ghtkn does when it gets no token; otherwise it runs the
# command after `--` with a fake GH_TOKEN, but only an absolute path, so a
# wrapper that hands over a bare `gh` cannot run itself through it.
stub_dir=$work_dir/stub
stub_log=$work_dir/ghtkn.log
mkdir -p "$stub_dir"
cat >"$stub_dir/ghtkn" <<STUB
#!/bin/sh
printf '%s\n' "\$@" >'$stub_log'
if [ -n "\${STUB_GHTKN_EXIT-}" ]; then exit "\$STUB_GHTKN_EXIT"; fi
while [ \$# -gt 0 ] && [ "\$1" != -- ]; do shift; done
shift
case \${1-} in
/*) GH_TOKEN=stub-ghtkn-token exec "\$@" ;;
*) echo "stub ghtkn: refusing to run '\${1-}' from PATH" >&2; exit 97 ;;
esac
STUB
chmod +x "$stub_dir/ghtkn"

new_home() { # <name> [<gh-app content>]   prints the home
  local home=$work_dir/$1
  mkdir -p "$home/.config/ghtkn"
  if (($# > 1)); then
    printf '%s' "$2" >"$home/.config/ghtkn/gh-app"
  fi
  echo "$home"
}

# Runs the wrapper; its stdout, stderr and status land in run.out, run.err
# and run.rc, and the stub's log, if it was called, in ghtkn.log.
run_gh() { # <home> [<VAR=value>...] -- <gh-arg>...
  local home=$1 vars=()
  shift
  while [[ $1 != -- ]]; do
    vars+=("$1")
    shift
  done
  shift
  rm -f "$stub_log"
  (cd "$work_dir" && env -i HOME="$home" PATH="$stub_dir:/usr/bin:/bin" ${vars[@]+"${vars[@]}"} \
    "$wrapper" "$@" >"$work_dir/run.out" 2>"$work_dir/run.err")
  echo $? >"$work_dir/run.rc"
}

out() { cat "$work_dir/run.out"; }
err() { tr '\n' ' ' <"$work_dir/run.err" | cut -c1-300; }
rc() { cat "$work_dir/run.rc"; }

ghtkn_not_called() { # <name>
  if [[ -e $stub_log ]]; then
    fail "$1" "ghtkn was called with: $(tr '\n' ' ' <"$stub_log")"
  else
    ok "$1"
  fi
}

app=example-org/write
home=$(new_home with-app "$app"$'\n')

# A caller's token reaches the real gh unchanged, and ghtkn is never asked.
run_gh "$home" GH_TOKEN=fake-gh-token -- auth token
is pass-gh-token fake-gh-token "$(out)"
ghtkn_not_called pass-gh-token-skips-ghtkn
run_gh "$home" GITHUB_TOKEN=fake-github-token -- auth token
is pass-github-token fake-github-token "$(out)"
ghtkn_not_called pass-github-token-skips-ghtkn

# Otherwise the token comes from ghtkn, for the app gh-app names. An empty
# or whitespace-only token is no token.
run_gh "$home" -- auth token
is ghtkn-token-reaches-gh "stub-ghtkn-token rc=0" "$(out) rc=$(rc)"
run_gh "$home" GH_TOKEN= -- auth token
is empty-gh-token-asks-ghtkn "stub-ghtkn-token rc=0" "$(out) rc=$(rc)"
run_gh "$home" GH_TOKEN=' ' GITHUB_TOKEN=$'\t' -- auth token
is blank-token-asks-ghtkn "stub-ghtkn-token rc=0" "$(out) rc=$(rc)"

# ghtkn gets the real gh by store path, never the wrapper, and every argument
# as given: one with a space, and a `--` of gh's own.
run_gh "$home" STUB_GHTKN_EXIT=0 -- pr view 'two words' -- --repo x
want=$(printf '%s\n' exec -e "GH_TOKEN:$app" -- "$real_gh" pr view 'two words' -- --repo x)
is ghtkn-args "$want" "$(cat "$stub_log" 2>/dev/null)"

# 111 is ghtkn's "no token": the status stays, and the hint says how to unlock.
run_gh "$home" STUB_GHTKN_EXIT=111 -- pr list
is no-token-status 111 "$(rc)"
if grep -qF "ghtkn agent unlock --enable-refresh" "$work_dir/run.err"; then
  ok no-token-unlock-hint
else
  fail no-token-unlock-hint "stderr: $(err)"
fi
run_gh "$home" STUB_GHTKN_EXIT=3 -- pr list
is other-status-kept "3 ''" "$(rc) '$(err)'"

# What gh runs without a token skips ghtkn, so a locked agent cannot stop it:
# help, the version, shell completion, config and aliases. Extensions may call
# the API, so they still ask ghtkn.
for word in '' -h --help help --version version completion __complete __completeNoDesc config alias; do
  args=(${word:+"$word"})
  [[ $word == __complete* ]] && args+=(pr '')
  run_gh "$home" STUB_GHTKN_EXIT=111 -- ${args[@]+"${args[@]}"}
  if [[ $(rc) == 0 && ! -e $stub_log ]]; then
    ok "token-free-${word:-no-argument}"
  else
    fail "token-free-${word:-no-argument}" "rc $(rc), stderr: $(err)"
  fi
done
run_gh "$home" STUB_GHTKN_EXIT=111 -- extension list
is extension-asks-ghtkn 111 "$(rc)"

# zsh's _gh runs `gh __complete` on each Tab with its stderr dropped, so with
# the agent locked it must still offer gh's commands.
zsh_bin=$(command -v zsh) || die "no zsh on PATH"
cat >"$work_dir/complete.zsh" <<'ZSH'
fpath=("$1" $fpath)
autoload -Uz compinit && compinit -u -D
_describe() { print -rl -- "${completions[@]}"; }
words=(gh pr '') CURRENT=3
_gh
ZSH
(cd "$work_dir" && env -i HOME="$home" PATH="$stub_dir:${wrapper%/*}:/usr/bin:/bin" STUB_GHTKN_EXIT=111 \
  "$zsh_bin" -f "$work_dir/complete.zsh" "${wrapper%/bin/gh}/share/zsh/site-functions" >"$work_dir/complete.out" 2>&1)
if grep -q '^list:' "$work_dir/complete.out"; then
  ok zsh-completes-without-token
else
  fail zsh-completes-without-token "output: $(tr '\n' ' ' <"$work_dir/complete.out" | cut -c1-300)"
fi

# ghtkn reads its files under XDG_CONFIG_HOME, and so does the wrapper.
xdg_home=$(new_home xdg-home)
mkdir -p "$work_dir/xdg/ghtkn"
echo example-org/other >"$work_dir/xdg/ghtkn/gh-app"
run_gh "$xdg_home" XDG_CONFIG_HOME="$work_dir/xdg" STUB_GHTKN_EXIT=0 -- status
is app-from-xdg-config-home GH_TOKEN:example-org/other "$(sed -n 3p "$stub_log" 2>/dev/null)"

# A gh-app written without a trailing newline still names its app.
run_gh "$(new_home no-newline "$app")" STUB_GHTKN_EXIT=0 -- status
is app-without-newline "GH_TOKEN:$app" "$(sed -n 3p "$stub_log" 2>/dev/null)"

# No app named: ghtkn would choose one itself, so the wrapper stops first.
for case in missing:no-app-file empty:empty-app-file; do
  if [[ ${case%%:*} == missing ]]; then
    bare=$(new_home "${case#*:}")
  else
    bare=$(new_home "${case#*:}" '')
  fi
  run_gh "$bare" -- auth token
  if [[ $(rc) != 0 ]] && grep -qF "$bare/.config/ghtkn/gh-app" "$work_dir/run.err"; then
    ok "${case#*:}"
  else
    fail "${case#*:}" "rc $(rc), stderr: $(err)"
  fi
  ghtkn_not_called "${case#*:}-skips-ghtkn"
done

# The render step, with a stub op that logs each call. whoami succeeds only
# with STUB_OP_SIGNED_IN set, and inject, which fails with STUB_OP_INJECT_FAILS
# set, reads the template from stdin alone, as op.exe on wsl must, and puts a
# placeholder in place of each reference.
render_bin=$(build "path:$repo_dir#ghtkn-render")/bin/ghtkn-render
[[ -x $render_bin ]] || die "ghtkn-render did not build: $(tail -n 5 "$work_dir/build.err")"
op_log=$work_dir/op.log
cat >"$stub_dir/op" <<STUB
#!/bin/sh
echo "\$1" >>'$op_log'
case \$1 in
whoami) [ -n "\${STUB_OP_SIGNED_IN-}" ] ;;
inject)
  [ -z "\${STUB_OP_INJECT_FAILS-}" ] || exit 1
  sed -E 's/\{\{ op:\/\/[^}]* \}\}/stub-client-id/g'
  ;;
*) exit 2 ;;
esac
STUB
chmod +x "$stub_dir/op"

render() { # <template> <target> <op-command> [<VAR=value>...]
  local template=$1 target=$2 op=$3
  shift 3
  rm -f "$op_log"
  (cd "$work_dir" && env -i HOME="$work_dir" PATH="$stub_dir:/usr/bin:/bin" "$@" \
    "$render_bin" "$template" "$target" "$op" </dev/null >"$work_dir/render.out" 2>"$work_dir/render.err")
  echo $? >"$work_dir/render.rc"
}
render_err() { tr '\n' ' ' <"$work_dir/render.err" | cut -c1-300; }
op_calls() { if [[ -e $op_log ]]; then tr '\n' ' ' <"$op_log"; fi; }
rendered() { # <template>   what the stub's inject makes of it
  sed -E 's/\{\{ op:\/\/[^}]* \}\}/stub-client-id/g' "$1"
}
# Exits 0 and warns, with no file written.
skipped() { # <name> <target> <reason>
  if [[ $(cat "$work_dir/render.rc") == 0 && ! -e $2 ]] && grep -qF "$3" "$work_dir/render.err"; then
    ok "$1"
  else
    fail "$1" "rc $(cat "$work_dir/render.rc"), $(ls -l "$2" 2>&1), stderr: $(render_err)"
  fi
}

template=$repo_dir/home/.config/ghtkn/ghtkn.personal.yaml.tpl
changed=$work_dir/changed.yaml.tpl
{ cat "$template"; echo "min_expiration: 1h"; } >"$changed"
target=$work_dir/render/ghtkn/ghtkn.yaml

render "$template" "$target" no-such-op STUB_OP_SIGNED_IN=1
skipped render-without-op "$target" "no-such-op is not installed"

render "$template" "$target" op
skipped render-signed-out "$target" "1Password is not signed in"
is render-signed-out-asks-only-whoami "whoami " "$(op_calls)"

render "$template" "$target" op STUB_OP_SIGNED_IN=1
is render-signed-in "0 $(rendered "$template")" "$(cat "$work_dir/render.rc") $(cat "$target" 2>&1)"
is render-mode -rw------- "$(ls -l "$target" 2>/dev/null | cut -c1-10)"
is render-leaves-only-the-file "ghtkn.yaml ghtkn.yaml.template-sha256" "$(ls "${target%/*}" | tr '\n' ' ' | sed 's/ $//')"

# Unchanged: op is never called, signed in or not, so no prompt can appear.
for state in signed-in signed-out; do
  vars=()
  [[ $state == signed-in ]] && vars=(STUB_OP_SIGNED_IN=1)
  render "$template" "$target" op ${vars[@]+"${vars[@]}"}
  is "render-unchanged-$state-calls-no-op" "0 '' ''" "$(cat "$work_dir/render.rc") '$(op_calls)' '$(render_err)'"
done
is render-unchanged-keeps-file "$(rendered "$template")" "$(cat "$target" 2>&1)"

render "$changed" "$target" op STUB_OP_SIGNED_IN=1
is render-template-changed "$(rendered "$changed")" "$(cat "$target" 2>&1)"

# Changed while signed out, or with inject failing: the old file stays, and
# the hash does not move on, so the next switch renders it.
render "$template" "$target" op
is render-changed-signed-out-keeps-file "0 $(rendered "$changed")" "$(cat "$work_dir/render.rc") $(cat "$target" 2>&1)"
render "$template" "$target" op STUB_OP_SIGNED_IN=1 STUB_OP_INJECT_FAILS=1
is render-inject-failed-keeps-file "0 $(rendered "$changed")" "$(cat "$work_dir/render.rc") $(cat "$target" 2>&1)"
if grep -qF "op inject failed" "$work_dir/render.err"; then ok render-inject-failed-warns; else fail render-inject-failed-warns "stderr: $(render_err)"; fi
is render-inject-failed-leaves-no-temp "ghtkn.yaml ghtkn.yaml.template-sha256" "$(ls "${target%/*}" | tr '\n' ' ' | sed 's/ $//')"
render "$template" "$target" op STUB_OP_SIGNED_IN=1
is render-retries-after-failure "$(rendered "$template")" "$(cat "$target" 2>&1)"

# A missing file is rendered even when the stored hash matches.
rm -f "$target"
render "$template" "$target" op STUB_OP_SIGNED_IN=1
is render-missing-file "$(rendered "$template")" "$(cat "$target" 2>&1)"

# A directory in the target's place, or a link to one, is refused before op
# runs; mv would leave a new copy inside it on every switch. A dangling link
# counts as absent, and the rendered file replaces it.
for kind in directory link-to-directory; do
  odd_target=$work_dir/render-$kind/ghtkn.yaml
  mkdir -p "$work_dir/render-$kind/elsewhere"
  if [[ $kind == directory ]]; then
    mkdir "$odd_target"
  else
    ln -s elsewhere "$odd_target"
  fi
  render "$template" "$odd_target" op STUB_OP_SIGNED_IN=1
  if [[ $(cat "$work_dir/render.rc") == 0 && -z $(op_calls) && -z $(ls -A "$odd_target/") ]] &&
    grep -qF "not a regular file" "$work_dir/render.err"; then
    ok "render-refuses-$kind"
  else
    fail "render-refuses-$kind" "rc $(cat "$work_dir/render.rc"), op: '$(op_calls)', inside: $(ls -A "$odd_target/" | tr '\n' ' '), stderr: $(render_err)"
  fi
done
mkdir -p "$work_dir/render-dangling"
ln -s nowhere "$work_dir/render-dangling/ghtkn.yaml"
render "$template" "$work_dir/render-dangling/ghtkn.yaml" op STUB_OP_SIGNED_IN=1
if [[ ! -L $work_dir/render-dangling/ghtkn.yaml && ! -e $work_dir/render-dangling/nowhere ]]; then
  is render-replaces-dangling-link "$(rendered "$template")" "$(cat "$work_dir/render-dangling/ghtkn.yaml" 2>&1)"
else
  fail render-replaces-dangling-link "$(ls -l "$work_dir/render-dangling" | tr '\n' ' ')"
fi

# The committed template: its client IDs are references, it selects the agent
# backend (ghtkn's default is the OS keyring), and it defines the app that
# gh-app.personal names for gh.
personal_app=$(cat "$repo_dir/home/.config/ghtkn/gh-app.personal")
if grep -qE '^ +client_id: "\{\{ op://[^}]+ \}\}"$' "$template" && ! grep -qE 'client_id: [^"]' "$template"; then
  ok template-client-ids-are-references
else
  fail template-client-ids-are-references "$(grep -n client_id "$template" | tr '\n' ' ')"
fi
is template-agent-backend "  type: agent" "$(grep -A1 -x 'backend:' "$template" | sed -n 2p)"
if grep -qxF "  - name: $personal_app" "$template"; then
  ok template-has-gh-app
else
  fail template-has-gh-app "no app named '$personal_app' in $template"
fi

echo "summary: $checks checks, $failures failed (repo $repo_dir)"
((failures == 0))
