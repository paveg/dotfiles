# @see https://wiki.archlinux.jp/index.php/XDG_Base_Directory
export XDG_CONFIG_HOME=$HOME/.config
export XDG_DATA_HOME=$HOME/.local/share

export SHELL=/bin/zsh
export EDITOR=nvim
export GHQ_ROOT="$HOME/src"

# zsh files
export DOTPATH="$GHQ_ROOT/github.com/paveg/dots"
export ZDOTPATH="$DOTPATH/zsh.d"
export ZMODPATH="$ZDOTPATH/mods"
export ZDOTDIR=$XDG_CONFIG_HOME/zsh

# CONFIG
export STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml
export ZELLIJ_CONFIG_DIR=$XDG_CONFIG_HOME/zellij

# DATA
export CARGO_HOME=$XDG_DATA_HOME/cargo

# Additinal environments
source $ZDOTPATH/.zshenv
