# @see https://wiki.archlinux.jp/index.php/XDG_Base_Directory
export XDG_CONFIG_HOME=$HOME/.config
export DOTPATH=$(pwd)

# Initialize zsh
export ZDOTDIR=$XDG_CONFIG_HOME/zsh
source $ZDOTDIR/.zshenv
