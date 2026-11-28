#!/usr/bin/env bash
# Check the gh wrapper that nix/ghtkn.nix builds (docs/adr/0004-github-auth-ghtkn.md),
# with no Nix switch and no real ghtkn: each run is `env -i` with a throwaway
# HOME and a stub ghtkn first on PATH, which records its arguments and runs the
# command it is handed with a fake token, and the real gh answers `gh auth
# token` with whatever token reached it. With GH_TOKEN or GITHUB_TOKEN set the
# wrapper runs the real gh directly; otherwise it asks ghtkn for the app that
# ~/.config/ghtkn/gh-app names, hands it the real gh rather than itself with
# every argument intact, keeps the exit status, says how to unlock the agent on
# 111, and refuses to run without an app. tests/packages.sh checks that the
# profile installs this same build.
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

# Otherwise the token comes from ghtkn, for the app gh-app names.
run_gh "$home" -- auth token
is ghtkn-token-reaches-gh "stub-ghtkn-token rc=0" "$(out) rc=$(rc)"

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

# ghtkn reads its files under XDG_CONFIG_HOME, and so does the wrapper.
xdg_home=$(new_home xdg-home)
mkdir -p "$work_dir/xdg/ghtkn"
echo example-org/other >"$work_dir/xdg/ghtkn/gh-app"
run_gh "$xdg_home" XDG_CONFIG_HOME="$work_dir/xdg" STUB_GHTKN_EXIT=0 -- status
is app-from-xdg-config-home GH_TOKEN:example-org/other "$(sed -n 3p "$stub_log" 2>/dev/null)"

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

echo "summary: $checks checks, $failures failed (repo $repo_dir)"
((failures == 0))
