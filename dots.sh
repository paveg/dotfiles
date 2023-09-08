#!/bin/bash

# @see https://wiki.archlinux.jp/index.php/XDG_Base_Directory
export XDG_CONFIG_HOME=$HOME/.config
export STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml

dotpath=$(pwd)
gitpath=$XDG_CONFIG_HOME/git

# zsh
if [ ! -f $HOME/.zshenv ]; then
	ln -sf $dotpath/.zshenv $HOME/.zshenv
	echo "Initialized $HOME/.zshenv"
fi
source ./zdotdir/symlink.sh

# starship
if [[ ! -f $STARSHIP_CONFIG ]]; then
  ln -sf $dotpath/starship.toml $STARSHIP_CONFIG
fi

# git
if [[ ! -d $gitpath ]]; then
		mkdir -p $gitpath
		echo "Created $gitpath"
fi
source ./git/symlink.sh

echo "[completed] Initialized dots!"
