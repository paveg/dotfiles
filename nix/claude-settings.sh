# Generate ~/.claude/settings.json and, on macOS, the managed-settings drop-in
# (docs/design.md "Generated settings.json"). nix/agents.nix prepends the store
# paths this reads: common_json, personal_json, hooks_json (the hooks built
# here), guard_hooks_json (the guards alone) and orca_json (the copy of Orca's
# entries). The file a target already holds is read only to list what changes:
# what it carries, Orca's entries included, never reaches the output.
# Usage: claude-settings settings <personal|work> <home-dir> [<drop-in>]
#        claude-settings managed <personal|work> <home-dir> <drop-in>
# Given a drop-in, `settings` writes nothing until the drop-in holds the guards,
# so a switch can never leave the guards in settings.json alone
# (spec/settings_writers.tla: GenWrite needs managedGuard).

usage() {
  echo "usage: claude-settings settings <personal|work> <home-dir> [<drop-in>]" >&2
  echo "       claude-settings managed <personal|work> <home-dir> <drop-in>" >&2
  exit 2
}

(($# == 3 || $# == 4)) || usage
mode=$1
profile=$2
home=$3
dropin=${4-}
case $mode in
  settings) ;;
  managed) [[ -n $dropin ]] || usage ;;
  *) usage ;;
esac

case $profile in
  personal) profile_json=$personal_json ;;
  work) profile_json=$home/.config/dots-work/claude/settings.work.json ;;
  *) usage ;;
esac

layers=("$common_json")
if [[ -f $profile_json ]]; then
  layers+=("$profile_json")
else
  echo "claude-settings: warning: $profile_json is missing, so settings.common.json is used alone" >&2
fi
# Values a personal host keeps out of this public repository, such as the
# telemetry collector's address. Optional, and never read on the work side.
local_json=$home/.config/dotfiles/claude/settings.local.json
if [[ $profile == personal && -f $local_json ]]; then
  layers+=("$local_json")
fi

# jq blames a parse error on the file it is reading when the error surfaces,
# which is the next layer when the broken one is not last.
for layer in "${layers[@]}"; do
  if ! error=$(jq empty "$layer" 2>&1); then
    echo "claude-settings: $layer is not valid JSON, so nothing is written: $error" >&2
    exit 1
  fi
done

# Objects merge key by key. Arrays concatenate with repeats dropped in
# first-seen order: jq's `*` would replace them, and `unique` would sort them.
# The root-written drop-in takes its deny list from layers the user can edit,
# so a layer that would replace an object or an array with another type, or
# add a deny entry that is not a string, stops the run before anything is
# written.
merge_layers() { # <json-file>...
  jq -n '
    def dedupe: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
    def refuse($message): "claude-settings: \(input_filename): \($message), so nothing is written\n" | halt_error(1);
    def merge($a; $b; $path):
      if ($a | type) == "object" and ($b | type) == "object" then
        reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = (if has($k) then merge(.[$k]; $b[$k]; $path + "." + $k) else $b[$k] end))
      elif ($a | type) == "array" and ($b | type) == "array" then $a + $b | dedupe
      elif ($a | type) == "array" or ($a | type) == "object" then
        refuse("\(if $path == "" then "the file" else $path end) has type \($b | type), but the layers before it hold an \($a | type)")
      else $b end;
    reduce inputs as $layer (input;
      if [$layer | .permissions? | objects | .deny | arrays | .[] | select(type != "string")] == [] then merge(.; $layer; "")
      else refuse(".permissions.deny holds an entry that is not a string") end)' "$@"
}

tmp=
trap 'rm -f "$tmp"' EXIT

# The changes go to the activation log, and any value may hold a credential
# whatever its key is called, so only the paths are printed, never a value from
# either side. Values are compared inside jq, and its errors, which can quote
# them, are dropped.
print_changes() { # <target> <content>
  if [[ $(jq -s length "$1" 2>/dev/null) != 1 ]]; then
    echo "claude-settings: $1: (not valid JSON, so not shown)"
    return
  fi
  jq -r --slurpfile old "$1" '
    def leaves: . as $doc
      | [paths((type | . != "object" and . != "array") or length == 0)
        | {key: tojson, value: (. as $p | $doc | getpath($p))}] | from_entries;
    def render: reduce .[] as $k (""; . + if ($k | type) == "number" then "[\($k)]"
      elif ($k | test("^[A-Za-z_][A-Za-z0-9_]*$")) then (if . == "" then $k else ".\($k)" end)
      else "[\($k | tojson)]" end);
    ($old[0] | leaves) as $a | leaves as $b
    | ([$a, $b | keys[]] | unique | map(fromjson) | sort)[] as $p
    | ($p | tojson) as $k
    | if ($a | has($k) | not) then "added"
      elif ($b | has($k) | not) then "removed"
      elif $a[$k] != $b[$k] then "changed"
      else empty end
    | "\(.): \($p | render)"' <<<"$2" 2>/dev/null || {
    echo "claude-settings: the changes to $1 could not be listed, so nothing is written" >&2
    exit 1
  }
}

# A regular file, never a link, replaced by a rename so a reader never sees half
# of it. The changes come first, so the switch shows what it is about to discard.
write_file() { # <target> <mode> <content>
  local target=$1 dir
  dir=$(dirname "$target")
  mkdir -p "$dir"
  if [[ -f $target && ! -L $target && $(cat "$target") == "$3" ]]; then
    chmod "$2" "$target"
    echo "claude-settings: $target is unchanged"
    return
  fi
  [[ ! -e $target ]] || print_changes "$target" "$3"
  tmp=$(mktemp "$dir/.${target##*/}.XXXXXX")
  printf '%s\n' "$3" >"$tmp"
  chmod "$2" "$tmp"
  mv -fT "$tmp" "$target"
  tmp=
  echo "claude-settings: wrote $target"
}

if [[ $mode == managed ]]; then
  # Root writes this from a profile the user can edit, so only the deny list
  # is taken from it: no other key belongs in managed scope.
  managed=$(merge_layers "${layers[@]}" | jq --slurpfile g "$guard_hooks_json" \
    '{hooks: $g[0].hooks, permissions: {deny: (.permissions.deny // [])}}')
  umask 022
  write_file "$dropin" 644 "$managed"
  exit 0
fi

if [[ -n $dropin ]] && ! jq -e --slurpfile g "$guard_hooks_json" \
  '[$g[0].hooks.PreToolUse[].hooks[]] - [.hooks.PreToolUse[]?.hooks[]?] == []' "$dropin" >/dev/null 2>&1; then
  echo "claude-settings: $dropin does not hold the guard hooks, so settings.json is left as it is" >&2
  exit 1
fi

settings=$(merge_layers "${layers[@]}" "$hooks_json" "$orca_json")
write_file "$home/.claude/settings.json" 600 "$settings"
