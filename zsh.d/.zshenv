# direnv
. "$HOME/.asdf/asdf.sh"
eval "$(direnv hook zsh)"

# Go
export GOPATH=$HOME
export ASDF_GOLANG_MOD_VERSION_ENABLED=true

# Rust
if [[ -f "$CARGO_HOME/env" ]]; then
  source $CARGO_HOME/env
fi

# fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS="--ansi --tiebreak=index --height 60% --layout=reverse --border --preview-window 'right:50%'"

# Binaries
path=(
  "$HOME/.local/bin"(N-/)
  "$GOPATH/bin"(N-/)
  "$path[@]"
)

# Others
## Append completions to fpath
fpath=(${ASDF_DIR}/completions $fpath)
