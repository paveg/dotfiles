export SHELL=/bin/zsh
# path configurations
typeset -Ug path PATH
path=(
  # Set homebrew path directly instead of `eval "(/opt/homebrew/bin/brew shellenv)"``
  /opt/homebrew/bin(N-/)
  /opt/homebrew/sbin(N-/)
  $HOME/bin(N-/)
  $HOME/.local/bin(N-/)
  $path[@]
)

# Locales
export LANG=C
export LC_CTYPE=ja_JP.UTF-8

export REPO_NAME=dotfiles

# Repository management is following https://github.com/x-motemen/ghq
export GHQ_ROOT=$HOME/repos

# Default configurations
export DOTDIR=$GHQ_ROOT/github.com/paveg/$REPO_NAME
export XDG_CONFIG_HOME=$HOME/.config
export EDITOR=nvim

# zsh
export ZDOTDIR="$DOTDIR/zsh.d"
export ZMODDIR="$ZDOTDIR/modules"

# https://github.com/junegunn/fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS="--ansi --tiebreak=index --height 60% --layout=reverse --border --preview-window 'right:50%'"

# https://starship.rs/
export STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml

# Language settings

## Go
export GOPATH=$HOME
export GOBIN=$GOPATH/bin

## Rust CARGO_HOME is default $HOME/.cargo

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
