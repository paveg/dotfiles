# asdf
source "$HOME/.asdf/asdf.sh"

# Go
export GOPATH=$HOME
export ASDF_GOLANG_MOD_VERSION_ENABLED=true

# Rust
source $CARGO_HOME/env

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
. "/home/ikezawa-ryota/.local/share/cargo/env"
