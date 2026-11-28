# The gh on PATH (docs/adr/0004-github-auth-ghtkn.md). nix/ghtkn.nix prepends
# gh, the real binary's store path, so ghtkn never runs this wrapper again;
# ghtkn itself comes from PATH.

# A caller that already holds a short-lived token, such as CI. Blanks are
# no token.
caller_token=${GH_TOKEN-}${GITHUB_TOKEN-}
if [[ -n ${caller_token//[[:space:]]/} ]]; then
  exec "$gh" "$@"
fi

# gh needs no token for these, and zsh's _gh runs `gh __complete` on each Tab.
# The cost: completions that call the API, such as `pr create --reviewer`, get none.
case ${1-} in
'' | -h | --help | help | --version | version | completion | __complete | __completeNoDesc | config | alias)
  exec "$gh" "$@"
  ;;
esac

# Without a name, ghtkn would pick an app itself: on work-mac the read app.
app_file=${XDG_CONFIG_HOME:-$HOME/.config}/ghtkn/gh-app
app=
if [[ -r $app_file ]]; then
  read -r app <"$app_file" || :
fi
if [[ -z $app ]]; then
  echo "gh: $app_file names no ghtkn app" >&2
  exit 1
fi

# Not exec: ghtkn replaces itself with gh, and 111 needs a hint afterwards.
status=0
ghtkn exec -e "GH_TOKEN:$app" -- "$gh" "$@" || status=$?
if ((status == 111)); then
  echo "gh: ghtkn has no token for $app: run 'ghtkn agent unlock --enable-refresh', or 'ghtkn auth $app' if it was never authenticated" >&2
fi
exit "$status"
