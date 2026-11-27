#!/usr/bin/env bash
# Break one condition of the settings generator or its wiring at a time, and
# require the checks in tests/agents.sh that cover it to fail. A surviving
# mutant means those checks prove nothing. orca-copy and work-example-rules are
# mutated through the files they guard. Each mutant must still build: a build
# that fails (shellcheck included) is reported as missed, not caught.
# Usage: tests/mutate-agents.sh
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/mutate.sh
source "$repo_dir/tests/lib/mutate.sh"

copy_repo() { # <dir>
  local entry
  for entry in flake.nix flake.lock hosts nix home profiles; do
    cp -R "$repo_dir/$entry" "$1/$entry"
  done
}

grade() { # <dir> <check>...
  local out
  out=$("$repo_dir/tests/agents.sh" "$1" 2>&1) || true
  # shellcheck disable=SC2086 # one check name per word
  mutate_checks_failed "$out" $2
}

run_mutant() { # <dir> <check>... <file> <old> <new>
  copy_repo "$1"
  mutate_apply "$1/$3" "$4" "$5" || return
  grade "$1" "$2"
}

run_mutant_jq() { # <dir> <check>... <file> <jq-filter>
  copy_repo "$1"
  jq "$4" "$1/$3" >"$1/$3.new" || return
  mv "$1/$3.new" "$1/$3"
  grade "$1" "$2"
}

expect_caught() { # <checks> <description> <file> <old> <new>
  mutant "$2" run_mutant "$1" "$3" "$4" "$5"
}

expect_caught_jq() { # <checks> <description> <file> <jq-filter>
  mutant "$2" run_mutant_jq "$1" "$3" "$4"
}

overrides() { # <kind>...   the override checks of each kind, on both layers and in both modes
  local kind layer mode
  for kind in "$@"; do
    for layer in local work; do
      for mode in managed settings; do
        printf '%s ' "override-$kind-$layer-$mode"
      done
    done
  done
}

generator=nix/claude-settings.sh

mutate_baseline 'the files as committed' "$repo_dir/tests/agents.sh"

expect_caught "common-deny-work $(overrides empty)" 'a profile array replaces the common one' "$generator" \
  'then $a + $b | dedupe' 'then $b'
expect_caught merge-dedupe 'arrays are concatenated with repeats kept' "$generator" \
  '$a + $b | dedupe' '$a + $b'
expect_caught merge-appends 'arrays are de-duplicated by sorting' "$generator" \
  '$a + $b | dedupe' '$a + $b | unique'
expect_caught 'orca-personal orca-orca-first' "Orca's entries are not written" nix/agents.nix \
  'orca_json=${./orca-hooks.json}' 'orca_json=${pkgs.writeText "no-orca.json" "{}"}'
expect_caught orca-personal "Orca's entries are carried over from the file being replaced" "$generator" \
  '"$hooks_json" "$orca_json")' \
  '"$hooks_json" <(jq --arg unused "$orca_json" '"'"'{hooks: ((.hooks // {}) | map_values(map(select(any(.hooks[]?; (.command // "") | test("agent-hooks/claude-hook"))))))}'"'"' "$home/.claude/settings.json" 2>/dev/null || echo "{}"))'
expect_caught orca-first-overwrites 'keys of the file being replaced are kept' "$generator" \
  'layers=("$common_json")' \
  'layers=("$common_json")
[[ ! -f $home/.claude/settings.json ]] || layers=("$home/.claude/settings.json" "$common_json")'
expect_caught merge-deep 'keys only a later layer has are dropped' "$generator" \
  '.[$k] = (if has($k) then merge(.[$k]; $b[$k]; $path + "." + $k) else $b[$k] end)' \
  'if has($k) then .[$k] = merge(.[$k]; $b[$k]; $path + "." + $k) else . end'
expect_caught "$(overrides null string object permissions-null)" 'a layer replaces an array or an object with another type' "$generator" \
  'elif ($a | type) == "array" or ($a | type) == "object" then' 'elif false then'
expect_caught "$(overrides null permissions-null)" 'a layer may set an array or an object to null' "$generator" \
  'elif ($a | type) == "array" or ($a | type) == "object" then' \
  'elif ($b | type) == "null" then $b elif ($a | type) == "array" or ($a | type) == "object" then'
expect_caught "$(overrides string)" 'a layer may replace an array with a string' "$generator" \
  'elif ($a | type) == "array" or ($a | type) == "object" then' \
  'elif ($b | type) == "string" then $b elif ($a | type) == "array" or ($a | type) == "object" then'
expect_caught "$(overrides object)" 'a layer may replace an array with an object' "$generator" \
  'elif ($a | type) == "array" or ($a | type) == "object" then' \
  'elif ($b | type) == "object" then $b elif ($a | type) == "array" or ($a | type) == "object" then'
expect_caught "$(overrides number)" 'a deny entry that is not a string is merged' "$generator" \
  'select(type != "string")] == [] then' 'select(type != "string")] == [] or true then'
expect_caught 'override-unparsable-local-settings override-unparsable-work-settings' \
  'a file that does not parse, followed by another, fails without its name' "$generator" \
  'if ! error=$(jq empty "$layer" 2>&1); then' 'if ! error=$(true); then'
expect_caught 'valid-json-personal valid-json-work dropin-json-personal dropin-json-work' \
  'the file written is not valid JSON' "$generator" \
  'printf '"'"'%s\n'"'"' "$3" >"$tmp"' 'printf '"'"'%s,\n'"'"' "$3" >"$tmp"'
expect_caught 'work-deny-work no-profile-warns no-telemetry-work' 'the work profile is read from the wrong place' "$generator" \
  'work) profile_json=$home/.config/dots-work/claude/settings.work.json ;;' \
  'work) profile_json=$personal_json ;;'
expect_caught no-profile-runs 'a missing work profile stops the switch' "$generator" \
  'if [[ -f $profile_json ]]; then' 'if true; then'
expect_caught 'regular-file-linked linked-target-untouched' 'the file is written through a link' "$generator" \
  'mv -fT "$tmp" "$target"' 'cat "$tmp" >"$target"'
expect_caught 'orca-first-diff leak-paths-added leak-paths-removed leak-paths-changed leak-unparsable-named' \
  'no change is printed before the write' "$generator" \
  '[[ ! -e $target ]] || print_changes "$target" "$3"' '[[ ! -e $target ]] || print_changes "$target" "$3" >/dev/null'
expect_caught 'leak-hidden-added leak-hidden-changed' 'the changes show the new value' "$generator" \
  '| "\(.): \($p | render)"' '| "\(.): \($p | render) \($b[$k])"'
expect_caught 'leak-hidden-removed leak-hidden-changed' 'the changes show the old value' "$generator" \
  '| "\(.): \($p | render)"' '| "\(.): \($p | render) \($a[$k])"'
expect_caught leak-paths-added 'an added path is not listed' "$generator" \
  'then "added"' 'then empty'
expect_caught 'leak-paths-removed orca-first-diff' 'a removed path is not listed' "$generator" \
  'then "removed"' 'then empty'
expect_caught leak-paths-changed 'a changed path is not listed' "$generator" \
  'then "changed"' 'then empty'
expect_caught 'leak-paths-added leak-paths-removed leak-paths-changed' 'an unchanged path is listed as changed' "$generator" \
  'elif $a[$k] != $b[$k] then' 'elif true then'
expect_caught 'leak-paths-added leak-paths-removed leak-paths-changed' 'only top-level keys are compared' "$generator" \
  '[paths((type | . != "object" and . != "array") or length == 0)' '[(keys_unsorted[] | [.])'
expect_caught 'leak-unparsable leak-unparsable-named' 'an old file that does not parse is shown' "$generator" \
  'echo "claude-settings: $1: (not valid JSON, so not shown)"' 'cat "$1"'
expect_caught 'leak-unparsable leak-unparsable-named' 'an old file that does not parse stops the switch' "$generator" \
  'if [[ $(jq -s length "$1" 2>/dev/null) != 1 ]]; then' 'if false; then'
expect_caught 'mode-personal mode-work mode-unchanged' 'settings.json is readable by every user' "$generator" \
  'write_file "$home/.claude/settings.json" 600 "$settings"' 'write_file "$home/.claude/settings.json" 644 "$settings"'
expect_caught mode-unchanged 'an unchanged settings.json keeps its old mode' "$generator" \
  '    chmod "$2" "$target"
' ''
expect_caught 'guard-block-sensitive-read-personal guard-block-sensitive-read-work dropin-guard-block-sensitive-read-work' \
  'a guard is left out' nix/agents.nix \
  '        block-sensitive-read
      ];' '      ];'
expect_caught 'guard-block-destructive-db-personal guard-block-sensitive-read-personal' 'the guards fail open' nix/agents.nix \
  '    onFailure = "block";
' ''
expect_caught reply-language-personal 'the reply-language hook is not the built one' nix/agents.nix \
  'command = pkgs.lib.getExe check-reply-language;' 'command = "check-reply-language";'
expect_caught reply-language-personal 'the reply-language checker fails closed' nix/agents.nix \
  'command = pkgs.lib.getExe check-reply-language;' 'command = pkgs.lib.getExe check-reply-language; onFailure = "block";'
expect_caught work-deny-not-personal 'the personal side gets the work profile' nix/agents.nix \
  'personal_json=${../home/.claude/settings.personal.json}' \
  'personal_json=${../profiles/work.example/claude/settings.work.json}'
expect_caught personal-profile-merged 'the personal profile is not merged' nix/agents.nix \
  'personal_json=${../home/.claude/settings.personal.json}' 'personal_json=${pkgs.writeText "empty.json" "{}"}'
expect_caught_jq no-ipv4-settings 'a collector address is in the tracked personal profile' \
  home/.claude/settings.personal.json '.env.OTEL_SERVICE_NAME = ([10, 0, 0, 1] | map(tostring) | join("."))'
expect_caught_jq no-telemetry-personal 'the tracked personal profile turns telemetry on' \
  home/.claude/settings.personal.json '.env.CLAUDE_CODE_ENABLE_TELEMETRY = "1"'
expect_caught_jq no-telemetry-personal 'the tracked personal profile names an exporter endpoint' \
  home/.claude/settings.personal.json '.env.OTEL_EXPORTER_OTLP_LOGS_ENDPOINT = "http://collector.invalid/v1/logs"'
expect_caught_jq no-telemetry-personal 'the tracked personal profile exports prompts' \
  home/.claude/settings.personal.json '.env.OTEL_LOG_USER_PROMPTS = "true"'
expect_caught_jq 'no-telemetry-work no-telemetry-no-profile' 'telemetry is turned on in the common settings' \
  home/.claude/settings.common.json '. + {env: {CLAUDE_CODE_ENABLE_TELEMETRY: "1"}}'
expect_caught_jq no-telemetry-work 'the work profile carries the exporter shape' \
  profiles/work.example/claude/settings.work.json '.env.OTEL_METRICS_EXPORTER = "otlp"'
expect_caught_jq env-strings-personal 'an env value is not a string' \
  home/.claude/settings.personal.json '.env.OTEL_METRICS_INCLUDE_SESSION_ID = false'
expect_caught 'telemetry-local leak-file' 'the local file is not read' "$generator" \
  'if [[ $profile == personal && -f $local_json ]]; then' 'if [[ $profile == personal && -f $local_json.off ]]; then'
expect_caught local-not-work 'the work side reads the local file' "$generator" \
  'if [[ $profile == personal && -f $local_json ]]; then' 'if [[ -f $local_json ]]; then'
expect_caught activation-work-mac 'work-mac activates the personal profile' hosts/work-mac.nix \
  'profile = "work";' 'profile = "personal";'
expect_caught 'activation-personal-mac activation-work-mac activation-wsl' 'no activation writes settings.json' nix/agents-home.nix \
  'home.activation.claudeSettings =' 'home.activation.claudeSettingsOff ='
expect_caught 'order-personal-mac order-work-mac' 'the drop-in is written after home-manager has written settings.json' nix/darwin.nix \
  'system.activationScripts.extraActivation.text = '"''" \
  'system.activationScripts.postActivation.text = pkgs.lib.mkAfter '"''"
expect_caught 'order-needs-dropin order-needs-guards' 'settings.json is written whatever the drop-in holds' "$generator" \
  'if [[ -n $dropin ]] && ! jq' 'if false && ! jq'
expect_caught order-needs-guards 'settings.json waits for the drop-in but not for its guards' "$generator" \
  "'[\$g[0].hooks.PreToolUse[].hooks[]] - [.hooks.PreToolUse[]?.hooks[]?] == []'" "'true'"
expect_caught order-after-dropin 'settings.json is refused even after the drop-in holds the guards' "$generator" \
  "'[\$g[0].hooks.PreToolUse[].hooks[]] - [.hooks.PreToolUse[]?.hooks[]?] == []'" "'false'"
expect_caught 'activation-personal-mac activation-work-mac' "home-manager on macOS does not wait for the drop-in" nix/agents-home.nix \
  'lib.optionalString (managedSettings != null)' 'lib.optionalString false'
expect_caught activation-wsl 'wsl is given a drop-in' flake.nix \
  'managedSettings = null;' 'managedSettings = "/etc/claude-code/managed-settings.d/50-dotfiles.json";'
expect_caught dropin-deny-work "the drop-in leaves out the profile's deny rules" "$generator" \
  'managed=$(merge_layers "${layers[@]}" |' 'managed=$(merge_layers "$common_json" |'
expect_caught 'dropin-only-guards-personal dropin-only-guards-work' 'the drop-in carries the checker too' "$generator" \
  'managed=$(merge_layers "${layers[@]}" | jq --slurpfile g "$guard_hooks_json"' \
  'managed=$(merge_layers "${layers[@]}" | jq --slurpfile g "$hooks_json"'
expect_caught 'dropin-keys-personal dropin-keys-work' 'the drop-in carries every profile key' "$generator" \
  "'{hooks: \$g[0].hooks, permissions: {deny: (.permissions.deny // [])}}'" "'. + {hooks: \$g[0].hooks}'"
expect_caught 'dropin-mode-personal dropin-mode-work' 'the drop-in is readable by its owner alone' "$generator" \
  'write_file "$dropin" 644 "$managed"' 'write_file "$dropin" 600 "$managed"'
expect_caught dropin-unwritable-fails 'a drop-in that cannot be written lets the switch go on' "$generator" \
  'write_file "$dropin" 644 "$managed"' 'write_file "$dropin" 644 "$managed" || true'
expect_caught 'links-personal-mac links-work-mac links-wsl' 'an entry of ~/.claude is not linked' nix/agents-home.nix \
  '    "statusline.sh"
' ''
expect_caught 'links-personal-mac links-work-mac links-wsl' 'Codex does not get the instructions' nix/agents-home.nix \
  '{ ".codex/AGENTS.md".source' '{ ".codex/AGENTS.off.md".source'
expect_caught links-work-mac "work-mac links the personal profile's skills" nix/agents-home.nix \
  'lib.genAttrs (skillsOf host.profile) (_: host.profile)' 'lib.genAttrs (skillsOf "personal") (_: "personal")'
expect_caught 'links-none-personal-mac links-none-work-mac links-none-wsl' 'an entry the repository lacks is linked' nix/agents-home.nix \
  'lib.filter (entry: builtins.pathExists (claudeSource + "/${entry}"))' 'lib.filter (entry: true)'
expect_caught links-clash 'a skill in common and a profile evaluates' nix/agents-home.nix \
  'lib.throwIf (clashes != [ ])' 'lib.throwIf false'
expect_caught_jq orca-copy "the copy of Orca's entries loses one" nix/orca-hooks.json 'del(.hooks.PostCompact)'
expect_caught_jq work-example-rules 'the work example adds no rule of its own' \
  profiles/work.example/claude/settings.work.json '.permissions.deny = []'

mutate_finish
