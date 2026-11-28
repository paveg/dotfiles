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
umask 077

skip() { # <reason>
  echo "ghtkn-render: warning: $1, so $target is not rendered; the next switch tries again" >&2
  exit 0
}
warn() { # <message>
  echo "ghtkn-render: warning: $1" >&2
  exit 0
}

hash=$(sha256sum <"$template")
hash=${hash%% *}
# Not through a link: chmod would reach whatever it points at.
if [[ -f $target && ! -L $target && $(cat "$stamp" 2>/dev/null) == "$hash" ]]; then
  chmod 600 "$target" || warn "$target could not be made private (mode 0600)"
  exit 0
fi

# mv would put the file inside a directory. A dangling link counts as absent.
if [[ -e $target && ! -f $target ]]; then
  skip "the target is not a regular file"
fi
command -v "$op" >/dev/null || skip "$op is not installed"
# Unverified: that whoami asks the app without raising a prompt (design.md).
"$op" whoami >/dev/null 2>&1 || skip "1Password is not signed in"

# The template comes on stdin: op.exe on wsl cannot open a Linux path. mktemp
# creates the file 0600, in the target's directory, so the mv is atomic. An
# exit on the way removes it, with whatever part of a client ID it holds; bash
# runs the EXIT trap when INT, TERM or HUP kills it too.
tmp=
trap '[[ -z $tmp ]] || rm -f -- "$tmp"' EXIT
mkdir -p "$(dirname "$target")" || skip "the target's directory could not be created"
tmp=$(mktemp "$target.XXXXXX") || skip "no temporary file could be created"
if ! "$op" inject <"$template" >"$tmp"; then
  skip "op inject failed"
fi
mv -fT "$tmp" "$target" || skip "the rendered file could not be moved into place"
# The hash goes the same way, so a link in its place is replaced, not followed.
{ tmp=$(mktemp "$stamp.XXXXXX") && echo "$hash" >"$tmp" && mv -fT "$tmp" "$stamp"; } ||
  warn "$target is rendered, but its hash could not be stored in $stamp, so the next switch renders it again"
