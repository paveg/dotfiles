export SHELL=/bin/zsh
export EDITOR=nvim

# @see https://wiki.archlinux.jp/index.php/XDG_Base_Directory
export XDG_CONFIG_HOME=$HOME/.config
export XDG_DATA_HOME=$HOME/.local/share

# CONFIG
export STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml

# DATA
export CARGO_HOME=$XDG_DATA_HOME/cargo

# Initialize zsh
export ZDOTDIR=$XDG_CONFIG_HOME/zsh
source $ZDOTDIR/.zshenv
