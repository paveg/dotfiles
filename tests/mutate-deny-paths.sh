#!/usr/bin/env bash
# Show that tests/deny-paths.sh refuses what it must and passes near misses.
# Each case is a scratch repository holding this checkout's tracked paths as
# empty files and its settings.common.json, plus one change: a tracked path
# added, or a rule added to or removed from the deny list.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
check=$repo_dir/tests/deny-paths.sh
settings=home/.claude/settings.common.json
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
cases=0
failures=0

scratch() { # prints a fresh scratch repository
  local dir path
  dir=$(mktemp -d "$work_dir/case.XXXX")
  git -C "$dir" init -q
  # git init sets this to true on a case-insensitive file system such as
  # macOS's; false leaves case folding to the check, as on Linux.
  git -C "$dir" config core.ignorecase false
  while IFS= read -r path; do
    mkdir -p "$dir/$(dirname "$path")"
    : >"$dir/$path"
  done < <(git -C "$repo_dir" ls-files)
  cp "$repo_dir/$settings" "$dir/$settings"
  git -C "$dir" add -f -A
  echo "$dir"
}

track() { # <repo> <path>
  mkdir -p "$1/$(dirname "$2")"
  : >"$1/$2"
  git -C "$1" add -f -- "$2"
}

set_rules() { # <repo> <jq filter over .permissions.deny>
  jq "$2" "$1/$settings" >"$1/rules.json"
  mv "$1/rules.json" "$1/$settings"
}

# A refusal counts only with a FAIL line holding <reason>, so a check that
# crashes, or refuses for another reason, does not pass a fail case.
expect() { # <pass|fail> <description> <repo> [reason]
  cases=$((cases + 1))
  if "$check" "$3" >"$work_dir/out" 2>&1; then
    got=pass
  elif grep '^FAIL: ' "$work_dir/out" | grep -qF -- "${4:-}"; then
    got=fail
  else
    got='fail without the expected reason'
  fi
  if [[ $got == "$1" ]]; then
    echo "ok: $2 ($got)"
  else
    failures=$((failures + 1))
    echo "FAIL: $2 should $1"
    sed 's/^/  /' "$work_dir/out"
  fi
}

expect pass 'this checkout' "$repo_dir"
expect pass 'a scratch copy of this checkout' "$(scratch)"

# One tracked path per repository-reaching rule, each named after the rule.
for path in foo.key home/foo.key docs/id_rsa nested/dir/id_ed25519 .env app/.env \
  .env.local app/.dev.vars .envrc .envrc.prod api_token.txt docs/tokens.md \
  server.pem deploy_key deploy_key.pub aws-credentials.json db-password.txt \
  docs/secrets.md docs/secrets/readme.md .netrc home/.npmrc DB-PASSWORD.txt Foo.KEY; do
  dir=$(scratch)
  track "$dir" "$path"
  expect fail "a tracked $path" "$dir" "$path"
done

# Near misses, and planned paths under home/ that home-anchored rules must not
# reach: ~/.ssh/** names the home directory's .ssh, not this checkout's copy.
for path in keys.md home/.ssh/config home/.config/gh/hosts.yml home/.config/op/config \
  home/.codex/auth.json home/.config/ghtkn/ghtkn.personal.yaml.tpl docs/env.md \
  key.txt monkey.sh; do
  dir=$(scratch)
  track "$dir" "$path"
  expect pass "a tracked $path" "$dir"
done

# The rules come from settings.common.json, not a copy inside the check.
dir=$(scratch)
set_rules "$dir" '.permissions.deny += ["Read(**/*.vault)"]'
track "$dir" notes.vault
expect fail 'a tracked path that only a rule added to the settings denies' "$dir" notes.vault

# A deny rule of one directory segment matches that directory at any depth;
# one of two segments stays at the root.
dir=$(scratch)
set_rules "$dir" '.permissions.deny += ["Read(vault/**)"]'
track "$dir" docs/vault/notes.md
expect fail 'a nested directory that a one-segment rule names' "$dir" docs/vault/notes.md

dir=$(scratch)
set_rules "$dir" '.permissions.deny += ["Read(docs/vault/**)"]'
track "$dir" home/docs/vault/notes.md
expect pass 'a nested copy of a two-segment rule' "$dir"

dir=$(scratch)
set_rules "$dir" '.permissions.deny -= ["Read(**/*.key)"]'
track "$dir" foo.key
expect pass 'a tracked foo.key once its rule is removed from the settings' "$dir"

dir=$(scratch)
set_rules "$dir" '.permissions.deny = []'
expect fail 'a deny list with no Read rules' "$dir" 'no Read'

dir=$(scratch)
rm "$dir/$settings"
expect fail 'no settings.common.json' "$dir" settings.common.json

for rule in 'Read(//etc/hosts)' 'Read(/docs/**)' 'Read(./notes)' 'Read(~/repos/**)' \
  'Read(~/**/.env)' 'Read(~/*/x)' 'Read(!x)'; do
  dir=$(scratch)
  set_rules "$dir" ".permissions.deny += [\"$rule\"]"
  expect fail "a rule the check cannot place, $rule" "$dir" "$rule"
done

dir=$(scratch)
set_rules "$dir" '.permissions.deny += ["Edit(**/*.md)"]'
expect pass 'a deny rule that is not a Read rule' "$dir"

echo "summary: $cases cases, $failures failed"
if ((failures > 0)); then exit 1; fi
