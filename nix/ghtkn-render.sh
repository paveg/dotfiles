# Render the personal ghtkn.yaml from its template with `op inject`
# (docs/design.md "Unattended host (Orca mobile)"). It renders only when the
# file is missing or the template changed, which the template's hash stored
# beside the file tells, so an unchanged template never raises a 1Password
# prompt; and only while 1Password is signed in. Every other outcome warns and
# exits 0, so the switch goes on and the next one tries again.
# Usage: ghtkn-render <template> <target> <op-command>

if (($# != 3)); then
  echo "usage: ghtkn-render <template> <target> <op-command>" >&2
  exit 2
fi
template=$1
target=$2
op=$3
stamp=$target.template-sha256

hash=$(sha256sum <"$template")
hash=${hash%% *}
if [[ -f $target && $(cat "$stamp" 2>/dev/null) == "$hash" ]]; then
  exit 0
fi

skip() { # <reason>
  echo "ghtkn-render: warning: $1, so $target is not rendered; the next switch tries again" >&2
  exit 0
}
# mv would put the file inside a directory. A dangling link counts as absent.
if [[ -e $target && ! -f $target ]]; then
  skip "the target is not a regular file"
fi
command -v "$op" >/dev/null || skip "$op is not installed"
# Unverified: that whoami asks the app without raising a prompt (design.md).
"$op" whoami >/dev/null 2>&1 || skip "1Password is not signed in"

# The template comes on stdin: op.exe on wsl cannot open a Linux path. mktemp
# creates the file 0600, in the target's directory, so the mv is atomic.
mkdir -p "$(dirname "$target")"
tmp=$(mktemp "$target.XXXXXX")
if ! "$op" inject <"$template" >"$tmp"; then
  rm -f "$tmp"
  skip "op inject failed"
fi
mv -fT "$tmp" "$target"
echo "$hash" >"$stamp"
