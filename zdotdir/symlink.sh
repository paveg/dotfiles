#!/bin/bash

basepath=$(cd $(dirname $0);pwd)
zdotpath=$HOME/.zsh

function initZsh () {
	if [ ! -d $zdotpath ]; then
		mkdir $zdotpath
		
	fi
	
	for zfile in zdotdir/.*
	do
		if [ ! -d $zfile -a $zfile != "." -a $zfile != ".." -a $zfile != ".git" ]; then
			file=$(basename $zfile)
			if [ $file == ".zshenv" ]; then
				echo "Symlink $basepath/$zfile to $HOME/"
				ln -sf $basepath/$zfile $HOME/
			else
				echo "Symlink $basepath/$zfile to $zdotpath/"
				ln -sf $basepath/$zfile $zdotpath/
			fi
		fi
	done
}

initZsh
