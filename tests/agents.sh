#!/usr/bin/env bash
# Check the generated ~/.claude/settings.json (docs/design.md "Generated
# settings.json") with no Nix switch: the generator built from <repo-dir> runs
# against temporary home directories, for the personal profile and for the work
# profile taken from profiles/work.example/. Each output must be a regular file
# holding valid JSON, the common deny rules in their order, the hooks by their
# built store paths, and Orca's entries exactly once, whatever the file held
# before; the work-only deny rules must reach the work side alone. Every host's
# home-manager activation must run the generator with that host's profile.
# Usage: tests/agents.sh [repo-dir]   (default: this checkout)
set -uo pipefail

harness_dir=$(cd "$(dirname "$0")/.." && pwd)
# Physical path: a `path:` flake reference rejects one that crosses a symlink.
repo_dir=$(cd "${1:-$harness_dir}" && pwd -P)
# Nix 2.33 fails a cached `eval --raw` of the darwin activation script, so a
# second run on an unchanged checkout would fail order-<host>.
nix_bin=(nix --extra-experimental-features 'nix-command flakes' --option eval-cache false)
common=$repo_dir/home/.claude/settings.common.json
orca=$repo_dir/nix/orca-hooks.json
work_example=$repo_dir/profiles/work.example
guards=(block-destructive-db block-sensitive-read)
# The design's host profiles: only work-mac carries the work profile.
host_profiles=(personal-mac:personal work-mac:work wsl:personal)

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

check() { # <name> <detail> <command>...
  local name=$1 detail=$2
  shift 2
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name" "$detail"; fi
}

# A broken build is an error in the harness, not a failed check.
die() { # <message>
  echo "ERROR: $1" >&2
  exit 2
}

build() { # <attr>
  "${nix_bin[@]}" build --no-link --print-out-paths "path:$repo_dir#$1" 2>"$work_dir/build.err" | tail -n 1
}

gen=$(build claude-settings)/bin/claude-settings
[[ -x $gen ]] || die "claude-settings did not build: $(tail -n 5 "$work_dir/build.err")"
# bash 3.2 (macOS) has no associative arrays, so each path sits in a file.
for name in "${guards[@]}" check-reply-language; do
  path=$(build "$name")/bin/$name
  [[ -x $path ]] || die "$name did not build"
  echo "$path" >"$work_dir/hook-$name"
done
hook_path() { # <name>
  cat "$work_dir/hook-$1"
}

generate() { # <name> <profile> <home>   writes <name>.out, <name>.err, <name>.rc
  "$gen" settings "$2" "$3" >"$work_dir/$1.out" 2>"$work_dir/$1.err"
  echo $? >"$work_dir/$1.rc"
}

mode_of() { # <file>
  ls -l "$1" 2>/dev/null | cut -c1-10
}

check_settings() { # <side> <settings-file>
  local side=$1 file=$2 name
  check "valid-json-$side" "$file is not a JSON object" jq -e 'type == "object"' "$file"
  check "regular-file-$side" "$file is not a regular file" test -f "$file" -a ! -L "$file"
  # The local file can carry telemetry headers, so no other user may read it.
  check "mode-$side" "$file is not of mode 600" test "$(mode_of "$file")" = -rw-------
  for name in "${guards[@]}"; do
    check "guard-$name-$side" "no Bash PreToolUse entry runs $(hook_path "$name") with onFailure block" \
      jq -e --arg c "$(hook_path "$name")" \
      '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?
        | select(.type == "command" and .command == $c and .onFailure == "block")] | length == 1' "$file"
  done
  # A checker fails open, so it must not carry onFailure.
  check "reply-language-$side" "no Stop entry runs $(hook_path check-reply-language) without onFailure" \
    jq -e --arg c "$(hook_path check-reply-language)" \
    '[.hooks.Stop[]? | .hooks[]? | select(.type == "command" and .command == $c)]
     | length == 1 and (.[0] | has("onFailure") | not)' "$file"
  check "orca-$side" "Orca's 16 entries are not each present exactly once" \
    jq -e --slurpfile o "$orca" \
    '.hooks as $h | [$o[0].hooks | to_entries[] | .key as $e | .value[] as $g
      | ($h[$e] // []) | map(select(. == $g)) | length] | length == 16 and all(. == 1)' "$file"
  check "common-deny-$side" "the deny list does not start with the common rules in their order" \
    jq -e --slurpfile c "$common" \
    '($c[0].permissions.deny) as $d | .permissions.deny[0:($d | length)] == $d' "$file"
}

# The harness compares against these files, so they must hold what they claim.
check orca-copy "nix/orca-hooks.json does not hold 16 entries that run Orca's claude-hook" \
  jq -e '[.hooks[][] | .hooks[] | .command | test("agent-hooks/claude-hook")] | length == 16 and all' "$orca"
work_only=$(jq -c --slurpfile c "$common" '.permissions.deny - $c[0].permissions.deny' \
  "$work_example/claude/settings.work.json" 2>/dev/null)
check work-example-rules "profiles/work.example adds no deny rule of its own" \
  jq -e 'length > 0' <<<"$work_only"

# Personal, on an empty home.
mkdir -p "$work_dir/personal"
generate personal personal "$work_dir/personal"
check_settings personal "$work_dir/personal/.claude/settings.json"

# Work, with the example profile placed where the bootstrap places the real one.
mkdir -p "$work_dir/work/.config"
cp -R "$work_example" "$work_dir/work/.config/dots-work"
generate work work "$work_dir/work"
check_settings work "$work_dir/work/.claude/settings.json"
check work-deny-work "a work-only deny rule is missing on the work side" \
  jq -e --argjson w "$work_only" '. as $s | $w - $s.permissions.deny == []' "$work_dir/work/.claude/settings.json"
check work-deny-not-personal "a work-only deny rule reached the personal side" \
  jq -e --argjson w "$work_only" '. as $s | $w - $s.permissions.deny == $w' "$work_dir/personal/.claude/settings.json"

# Telemetry is off unless an untracked local file on a personal host supplies
# it: tracked settings carry no address, no switch that turns it on, and none
# of the variables that export prompts or tool content and arguments.
no_telemetry='[.env // {} | keys[] | select(. == "CLAUDE_CODE_ENABLE_TELEMETRY" or startswith("OTEL_EXPORTER_")
  or . == "OTEL_LOG_USER_PROMPTS" or . == "OTEL_LOG_TOOL_CONTENT" or . == "OTEL_LOG_TOOL_DETAILS")] == []'
# The work side carries none of it, not even the exporter shape.
no_telemetry_work='[.env // {} | keys[] | select(. == "CLAUDE_CODE_ENABLE_TELEMETRY" or startswith("OTEL_"))] == []'
ipv4='(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)'
ipv4_files=$(grep -rlE --include='*.json' "$ipv4" "$repo_dir/home" "$repo_dir/profiles" "$repo_dir/nix" 2>/dev/null)
if [[ -z $ipv4_files ]]; then ok no-ipv4-settings; else fail no-ipv4-settings "an IPv4 address is in ${ipv4_files//$'\n'/, }"; fi
check personal-profile-merged "a key of settings.personal.json is missing from the personal side" \
  jq -e --slurpfile p "$repo_dir/home/.claude/settings.personal.json" \
  '. as $s | [$p[0] | paths(scalars)] | all(. as $path | $s | getpath($path) == ($p[0] | getpath($path)))' \
  "$work_dir/personal/.claude/settings.json"
check no-telemetry-personal "with no local file, the personal side turns telemetry on or names an exporter or a content variable" \
  jq -e "$no_telemetry" "$work_dir/personal/.claude/settings.json"
check no-telemetry-work "the work side carries a telemetry variable" \
  jq -e "$no_telemetry_work" "$work_dir/work/.claude/settings.json"
check env-strings-personal "an env value is not a string" \
  jq -e '.env // {} | all(.[]; type == "string")' "$work_dir/personal/.claude/settings.json"

# The local file turns telemetry on for the personal profile, and only there.
local_probe='{"env": {"CLAUDE_CODE_ENABLE_TELEMETRY": "1", "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT": "http://collector.invalid/v1/metrics"}}'
for side in personal work; do
  mkdir -p "$work_dir/local-$side/.config/dotfiles/claude"
  echo "$local_probe" >"$work_dir/local-$side/.config/dotfiles/claude/settings.local.json"
done
cp -R "$work_example" "$work_dir/local-work/.config/dots-work"
generate local-personal personal "$work_dir/local-personal"
generate local-work work "$work_dir/local-work"
check telemetry-local "the personal side did not take telemetry from the local file" \
  jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY == "1" and .env.OTEL_EXPORTER_OTLP_METRICS_ENDPOINT == "http://collector.invalid/v1/metrics"' \
  "$work_dir/local-personal/.claude/settings.json"
check local-not-work "the work side took telemetry from the local file" \
  jq -e "$no_telemetry_work" "$work_dir/local-work/.claude/settings.json"

# Work, before the work profile exists: the common file alone, with a warning.
mkdir -p "$work_dir/no-profile"
generate no-profile work "$work_dir/no-profile"
check no-profile-runs "the generator failed without a work profile" test "$(cat "$work_dir/no-profile.rc")" = 0
check no-profile-warns "no warning names the missing work profile" grep -q 'settings.work.json is missing' "$work_dir/no-profile.err"
check_settings no-profile "$work_dir/no-profile/.claude/settings.json"
check no-telemetry-no-profile "the work side without its profile carries a telemetry variable" \
  jq -e "$no_telemetry_work" "$work_dir/no-profile/.claude/settings.json"

# A work profile that repeats a common rule and adds keys of its own.
mkdir -p "$work_dir/merge/.config/dots-work/claude"
jq -n --slurpfile c "$common" \
  '{permissions: {deny: [$c[0].permissions.deny[0], "Bash(merge-probe *)"], ask: ["Bash(ask-probe *)"]}, env: {MERGE_PROBE: "1"}}' \
  >"$work_dir/merge/.config/dots-work/claude/settings.work.json"
generate merge work "$work_dir/merge"
merged=$work_dir/merge/.claude/settings.json
check merge-dedupe "a rule in both layers is not there exactly once" \
  jq -e --slurpfile c "$common" '[.permissions.deny[] | select(. == $c[0].permissions.deny[0])] | length == 1' "$merged"
check merge-appends "the profile's own rule does not follow the common rules" \
  jq -e --slurpfile c "$common" '.permissions.deny == $c[0].permissions.deny + ["Bash(merge-probe *)"]' "$merged"
check merge-deep "keys only the profile has did not survive the merge" \
  jq -e '.permissions.ask == ["Bash(ask-probe *)"] and .env.MERGE_PROBE == "1"' "$merged"

# After Orca has merged its entries (and its theme sync its theme key), a
# switch overwrites the file and keeps Orca's entries, once each.
mkdir -p "$work_dir/orca-first/.claude"
jq '. + {theme: "dark"}' "$orca" >"$work_dir/orca-first/.claude/settings.json"
generate orca-first personal "$work_dir/orca-first"
check_settings orca-first "$work_dir/orca-first/.claude/settings.json"
check orca-first-overwrites "a key the generator does not own survived the switch" \
  jq -e 'has("theme") | not' "$work_dir/orca-first/.claude/settings.json"
diff_line=$(grep -n '^removed: theme$' "$work_dir/orca-first.out" | head -n 1 | cut -d: -f1)
wrote_line=$(grep -n 'claude-settings: wrote ' "$work_dir/orca-first.out" | head -n 1 | cut -d: -f1)
check orca-first-diff "the line naming the dropped theme key was not printed before the write" \
  test -n "$diff_line" -a -n "$wrote_line" -a "${diff_line:-0}" -lt "${wrote_line:-0}"

# A settings.json that is a link (as a store-linked file would be) becomes a
# regular file, and what it pointed to is left alone.
mkdir -p "$work_dir/linked/.claude"
echo '{"linked": true}' >"$work_dir/link-target.json"
ln -s "$work_dir/link-target.json" "$work_dir/linked/.claude/settings.json"
generate linked personal "$work_dir/linked"
check_settings linked "$work_dir/linked/.claude/settings.json"
check linked-target-untouched "the generator wrote through the link" \
  test "$(cat "$work_dir/link-target.json")" = '{"linked": true}'

# A file an earlier switch left at mode 644 is narrowed even when its content
# is unchanged.
mkdir -p "$work_dir/mode-upgrade/.claude"
cp "$work_dir/personal/.claude/settings.json" "$work_dir/mode-upgrade/.claude/settings.json"
chmod 644 "$work_dir/mode-upgrade/.claude/settings.json"
generate mode-upgrade personal "$work_dir/mode-upgrade"
check mode-unchanged "an unchanged settings.json of mode 644 was not narrowed to 600" \
  test "$(mode_of "$work_dir/mode-upgrade/.claude/settings.json")" = -rw------- \
  -a -n "$(grep 'is unchanged' "$work_dir/mode-upgrade.out")"

# The changes a switch prints name the paths and show no value, whichever side
# holds it and whatever its key is called, while the file holds the new values.
marker=leak-probe-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
leak_json() { # <value>
  jq -n --arg v "$1" '{env: {DB_PASSWORD: $v, HTTPS_PROXY: "http://probe:\($v)@proxy.invalid:3128"},
    apiKeyHelper: "echo \($v)",
    hooks: {Notification: [{matcher: "", hooks: [{type: "command",
      command: "curl -H '\''Authorization: Bearer \($v)'\'' https://hook.invalid"}]}]}}'
}
leak_paths='apiKeyHelper env.DB_PASSWORD env.HTTPS_PROXY hooks.Notification[0].hooks[0].command hooks.Notification[0].hooks[0].type hooks.Notification[0].matcher'
leak_changed='apiKeyHelper env.DB_PASSWORD env.HTTPS_PROXY hooks.Notification[0].hooks[0].command'

leak_case() { # <case> <old-value|-> <new-value|->   "-" leaves that side without the fixture
  local home=$work_dir/leak-$1
  mkdir -p "$home/.claude" "$home/.config/dotfiles/claude"
  if [[ $2 == - ]]; then
    cp "$work_dir/personal/.claude/settings.json" "$home/.claude/settings.json"
  else
    leak_json "$2" | jq -s '.[0] * .[1]' "$work_dir/personal/.claude/settings.json" - >"$home/.claude/settings.json"
  fi
  [[ $3 == - ]] || leak_json "$3" >"$home/.config/dotfiles/claude/settings.local.json"
  generate "leak-$1" personal "$home"
}

leak_hidden() { # <case>   ran, wrote, and printed no value
  [[ $(cat "$work_dir/leak-$1.rc") == 0 ]] && grep -q 'claude-settings: wrote ' "$work_dir/leak-$1.out" &&
    ! grep -qF -- "$marker" "$work_dir/leak-$1.out" "$work_dir/leak-$1.err"
}

leak_lines() { # <case>   the change lines it printed, sorted
  grep -E '^(added|removed|changed): ' "$work_dir/leak-$1.out" | LC_ALL=C sort
}

expected_lines() { # <verb> <paths>
  local path
  for path in $2; do echo "$1: $path"; done | LC_ALL=C sort
}

leak_case added - "$marker-new"
leak_case removed "$marker-old" -
leak_case changed "$marker-old" "$marker-new"
for case in added removed changed; do
  check "leak-hidden-$case" "the $case run failed, or printed a value" leak_hidden "$case"
done
check leak-paths-added "the paths only the new file holds are not each listed as added" \
  test "$(leak_lines added)" = "$(expected_lines added "$leak_paths")"
check leak-paths-removed "the paths only the old file holds are not each listed as removed" \
  test "$(leak_lines removed)" = "$(expected_lines removed "$leak_paths")"
check leak-paths-changed "the paths whose value changed are not each listed as changed" \
  test "$(leak_lines changed)" = "$(expected_lines changed "$leak_changed")"
check leak-file "settings.json does not hold the new values" \
  jq -e --arg v "$marker-new" '.env.DB_PASSWORD == $v and .apiKeyHelper == "echo \($v)"' \
  "$work_dir/leak-changed/.claude/settings.json"

# An old file that does not parse is named, but not shown.
mkdir -p "$work_dir/leak-unparsable/.claude"
printf '{"env": {"DB_PASSWORD": "%s"' "$marker" >"$work_dir/leak-unparsable/.claude/settings.json"
generate leak-unparsable personal "$work_dir/leak-unparsable"
check leak-unparsable "the run over an old file that does not parse failed, or showed a value" \
  leak_hidden unparsable
check leak-unparsable-named "an old file that does not parse was not said to be invalid" \
  grep -qF '(not valid JSON, so not shown)' "$work_dir/leak-unparsable.out"

# The macOS drop-in: the guards and the merged deny list, and nothing else.
for side in personal work; do
  dropin=$work_dir/dropin-$side/managed-settings.d/50-dotfiles.json
  "$gen" managed "$side" "$work_dir/$side" "$dropin" >"$work_dir/dropin-$side.out" 2>&1
  check "dropin-json-$side" "$dropin is not a JSON object" jq -e 'type == "object"' "$dropin"
  check "dropin-mode-$side" "$dropin is not a world-readable regular file of mode 644" \
    test "$(ls -l "$dropin" 2>/dev/null | cut -c1-10)" = -rw-r--r--
  for name in "${guards[@]}"; do
    check "dropin-guard-$name-$side" "the drop-in does not run $(hook_path "$name") with onFailure block" \
      jq -e --arg c "$(hook_path "$name")" \
      '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?
        | select(.type == "command" and .command == $c and .onFailure == "block")] | length == 1' "$dropin"
  done
  check "dropin-only-guards-$side" "the drop-in holds a hook other than the guards" \
    jq -e '(.hooks | keys) == ["PreToolUse"] and ([.hooks[][].hooks[]] | length) == 2' "$dropin"
  check "dropin-keys-$side" "the drop-in holds a key other than hooks and permissions.deny" \
    jq -e 'keys == ["hooks", "permissions"] and (.permissions | keys) == ["deny"]' "$dropin"
  check "dropin-deny-$side" "the drop-in's deny list is not the one settings.json gets on this side" \
    jq -e --slurpfile s "$work_dir/$side/.claude/settings.json" '.permissions.deny == $s[0].permissions.deny' "$dropin"
done

# A drop-in that cannot be written fails, so the activation stops before it
# reaches settings.json.
mkdir -p "$work_dir/locked"
chmod 555 "$work_dir/locked"
"$gen" managed personal "$work_dir/personal" "$work_dir/locked/managed-settings.d/50-dotfiles.json" >/dev/null 2>&1
check dropin-unwritable-fails "writing the drop-in into a read-only directory succeeded" test $? != 0
chmod 755 "$work_dir/locked"

# Given the drop-in's path, the generator writes settings.json only once the
# drop-in holds the guards (spec/settings_writers.tla: GenWrite needs
# managedGuard).
mkdir -p "$work_dir/order"
"$gen" settings personal "$work_dir/order" "$work_dir/no-such-dir/50-dotfiles.json" >/dev/null 2>&1
check order-needs-dropin "settings.json was written while the drop-in is missing" \
  test $? != 0 -a ! -e "$work_dir/order/.claude/settings.json"
echo '{}' >"$work_dir/empty-dropin.json"
"$gen" settings personal "$work_dir/order" "$work_dir/empty-dropin.json" >/dev/null 2>&1
check order-needs-guards "settings.json was written while the drop-in lacks the guards" \
  test $? != 0 -a ! -e "$work_dir/order/.claude/settings.json"
"$gen" settings personal "$work_dir/order" "$work_dir/dropin-personal/managed-settings.d/50-dotfiles.json" >/dev/null 2>&1
check order-after-dropin "settings.json was not written after the drop-in" \
  test $? = 0 -a -f "$work_dir/order/.claude/settings.json"

# A layer the user can edit adds deny rules but never removes a common one. An
# empty list changes nothing; a value of another type, or a file that does not
# parse, fails the run with the file's name and writes nothing.
override_json() { # <kind>
  case $1 in
    null) echo '{"permissions": {"deny": null}}' ;;
    string) echo '{"permissions": {"deny": "Bash(override-probe *)"}}' ;;
    object) echo '{"permissions": {"deny": {}}}' ;;
    number) echo '{"permissions": {"deny": ["Bash(override-probe *)", 1]}}' ;;
    permissions-null) echo '{"permissions": null}' ;;
    unparsable) echo '{"permissions": {' ;;
    empty) echo '{"permissions": {"deny": []}}' ;;
  esac
}

failed_closed() { # <rc> <stderr-file> <layer-file> <target>
  [[ $1 != 0 ]] && grep -qF -- "$3" "$2" && [[ ! -e $4 ]]
}

for entry in local:personal:.config/dotfiles/claude/settings.local.json work:work:.config/dots-work/claude/settings.work.json; do
  layer=${entry%%:*}
  profile=${entry#*:}
  layer_file=${profile#*:}
  profile=${profile%%:*}
  for kind in null string object number permissions-null unparsable empty; do
    home=$work_dir/override-$kind-$layer
    mkdir -p "$(dirname "$home/$layer_file")"
    override_json "$kind" >"$home/$layer_file"
    "$gen" managed "$profile" "$home" "$home/dropin.json" >/dev/null 2>"$home/managed.err"
    managed_rc=$?
    "$gen" settings "$profile" "$home" >/dev/null 2>"$home/settings.err"
    settings_rc=$?
    if [[ $kind == empty ]]; then
      check "override-empty-$layer-managed" "an empty deny list in the $layer layer changed the drop-in's common rules" \
        jq -e --slurpfile c "$common" '.permissions.deny == $c[0].permissions.deny' "$home/dropin.json"
      check "override-empty-$layer-settings" "an empty deny list in the $layer layer changed settings.json's common rules" \
        jq -e --slurpfile c "$common" '.permissions.deny == $c[0].permissions.deny' "$home/.claude/settings.json"
      continue
    fi
    check "override-$kind-$layer-managed" "the $kind override in the $layer layer did not fail the drop-in closed, naming the file" \
      failed_closed "$managed_rc" "$home/managed.err" "$home/$layer_file" "$home/dropin.json"
    check "override-$kind-$layer-settings" "the $kind override in the $layer layer did not fail settings.json closed, naming the file" \
      failed_closed "$settings_rc" "$home/settings.err" "$home/$layer_file" "$home/.claude/settings.json"
  done
done

line_of() { # <regex> <text>   the first matching line number, or nothing
  grep -nE -- "$1" <<<"$2" | head -n 1 | cut -d: -f1
}

# Each host's activation runs the generator with the host's profile. On macOS
# the system activation, which runs as root, writes the drop-in before it
# starts home-manager, and home-manager's run requires the drop-in.
dropin_path='/Library/Application Support/ClaudeCode/managed-settings.d/50-dotfiles.json'
gen_re='/nix/store/[a-z0-9]+-claude-settings/bin/claude-settings'
for entry in "${host_profiles[@]}"; do
  host=${entry%%:*}
  profile=${entry#*:}
  user=$("${nix_bin[@]}" eval --raw --file "$repo_dir/hosts/$host.nix" user 2>/dev/null)
  if [[ $host == wsl ]]; then
    attr="homeConfigurations.\"$user@wsl\".config.home.activation.claudeSettings.data"
    home=/home/$user
    want="^ *run $gen_re settings $profile $home *\$"
  else
    attr="darwinConfigurations.$host.config.home-manager.users.\"$user\".home.activation.claudeSettings.data"
    home=/Users/$user
    want="^ *run $gen_re settings $profile $home $dropin_path *\$"
  fi
  # Quoting aside: escapeShellArg quotes only what needs it.
  text=$("${nix_bin[@]}" eval --raw "path:$repo_dir#$attr" 2>"$work_dir/eval.err" | tr -d "'")
  if [[ -n $(line_of "$want" "$text") ]]; then
    ok "activation-$host"
  else
    fail "activation-$host" "no line matches '$want': ${text:-$(tail -n 3 "$work_dir/eval.err")}"
  fi
  [[ $host == wsl ]] && continue
  script=$("${nix_bin[@]}" eval --raw "path:$repo_dir#darwinConfigurations.$host.config.system.activationScripts.script.text" \
    2>"$work_dir/eval.err" | tr -d "'")
  managed_line=$(line_of "^ *$gen_re managed $profile $home $dropin_path *\$" "$script")
  hm_line=$(line_of 'Activating home-manager configuration' "$script")
  root_settings_line=$(line_of "$gen_re settings" "$script")
  if [[ -n $managed_line && -n $hm_line && -z $root_settings_line ]] && ((managed_line < hm_line)); then
    ok "order-$host"
  else
    fail "order-$host" "the system activation does not write the drop-in before home-manager (drop-in line '${managed_line}', home-manager line '${hm_line}', root settings.json line '${root_settings_line}')"
  fi
done

# Links. The repository has none of the linked entries yet, so a copy gets
# placeholders: each ~/.claude entry, and one skill per profile directory.
links_repo=$work_dir/links-repo
mkdir -p "$links_repo"
for entry in flake.nix flake.lock hosts nix home profiles; do
  cp -R "$repo_dir/$entry" "$links_repo/$entry"
done
claude_src=$links_repo/home/.claude
mkdir -p "$claude_src/rules" "$claude_src/agents" "$claude_src/references"
touch "$claude_src/CLAUDE.md" "$claude_src/statusline.sh" "$claude_src/rules/placeholder.md" \
  "$claude_src/agents/placeholder.md" "$claude_src/references/placeholder.md"
for skill in common:shared-skill personal:personal-skill work:work-skill; do
  mkdir -p "$claude_src/skills/${skill%%:*}/${skill#*:}"
  touch "$claude_src/skills/${skill%%:*}/${skill#*:}/SKILL.md"
done

link_names() { # <repo> <host>   the sorted ~/.claude and ~/.codex names home.file holds
  local user attr
  user=$("${nix_bin[@]}" eval --raw --file "$1/hosts/$2.nix" user 2>/dev/null)
  if [[ $2 == wsl ]]; then
    attr="homeConfigurations.\"$user@wsl\".config.home.file"
  else
    attr="darwinConfigurations.$2.config.home-manager.users.\"$user\".home.file"
  fi
  "${nix_bin[@]}" eval --json "path:$1#$attr" --apply builtins.attrNames 2>"$work_dir/eval.err" |
    jq -r '[.[] | select(startswith(".claude/") or startswith(".codex/"))] | sort | join(" ")'
}

entries='.claude/CLAUDE.md .claude/agents .claude/references .claude/rules .claude/statusline.sh .codex/AGENTS.md'
for entry in "${host_profiles[@]}"; do
  host=${entry%%:*}
  profile=${entry#*:}
  want=$(printf '%s\n' $entries .claude/skills/shared-skill ".claude/skills/$profile-skill" | LC_ALL=C sort | tr '\n' ' ')
  got=$(link_names "$links_repo" "$host")
  if [[ "$got " == "$want" ]]; then ok "links-$host"; else fail "links-$host" "want '$want', got '$got'"; fi
  got=$(link_names "$repo_dir" "$host")
  if [[ -z $got ]]; then ok "links-none-$host"; else fail "links-none-$host" "the repository has no linked entry, but home.file holds '$got'"; fi
done

# A skill in common and in a profile is an evaluation error on that profile's hosts.
mkdir -p "$claude_src/skills/personal/shared-skill"
got=$(link_names "$links_repo" personal-mac)
if [[ -z $got ]] && grep -q 'shared-skill' "$work_dir/eval.err"; then
  ok links-clash
else
  fail links-clash "a skill in common and personal evaluated, or the error does not name it: '$got'"
fi

echo "summary: $checks checks, $failures failed"
((failures == 0))
