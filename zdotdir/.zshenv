# asdf
. "$HOME/.asdf/asdf.sh"
# append completions to fpath
fpath=(${ASDF_DIR}/completions $fpath)

# Go
export GOPATH=$HOME
export PATH=$PATH:$GOPATH/bin # Add GOPATH/bin to PATH for scripting
export ASDF_GOLANG_MOD_VERSION_ENABLED=true

# Rust
source $CARGO_HOME/env

# fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS="--ansi --tiebreak=index --height 70% --layout=reverse --border --preview-window 'right:50%'"
