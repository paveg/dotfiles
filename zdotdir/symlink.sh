#!/bin/bash

basepath=$(cd $(dirname $0);pwd)
xdgpath=$HOME/.config
zdotpath=$xdgpath/zsh

function initZsh () {
	if [ ! -d $zdotpath ]; then
		mkdir $zdotpath

	fi

	for zfile in zdotdir/.*
	do
		if [ ! -d $zfile -a $zfile != "." -a $zfile != ".." -a $zfile != ".git" ]; then
			echo "Symlink $basepath/$zfile to $zdotpath/"
			ln -sf $basepath/$zfile $zdotpath/
		fi
	done
}

initZsh
