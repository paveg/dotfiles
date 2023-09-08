#!/bin/bash

dotpath=$(pwd)
if [ ! -f $HOME/.zshenv ]; then
	echo "Symlink $dotpath/.zshenv to $HOME/.zshenv"
	ln -sf $dotpath/.zshenv $HOME/.zshenv
fi
source ./zdotdir/symlink.sh
