#!/bin/bash

# @see https://wiki.archlinux.jp/index.php/XDG_Base_Directory
export XDG_CONFIG_HOME=$HOME/.config
export STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml

dotpath=$(pwd)
if [ ! -f $HOME/.zshenv ]; then
	echo "Symlink $dotpath/.zshenv to $HOME/.zshenv"
	ln -sf $dotpath/.zshenv $HOME/.zshenv
fi
source ./zdotdir/symlink.sh

if [[ ! -f $STARSHIP_CONFIG ]]; then
  ln -sf $dotpath/starship.toml $STARSHIP_CONFIG
fi
