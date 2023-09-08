#!/bin/bash

basepath=$(cd $(dirname $0);pwd)
xdgpath=$HOME/.config
zdotpath=$xdgpath/zsh

function initZsh () {
	echo "[info] Initialize zsh"
	if [ ! -d $zdotpath ]; then
		mkdir $zdotpath

	fi

	for zfile in zdotdir/.*
	do
		file=$(dirname $zfile)
		if [ ! -d $zfile -a $file != "." -a $file != ".." -a $file != ".git" ]; then
			# echo "Symlink $basepath/$zfile to $zdotpath/"
			ln -sf $basepath/$zfile $zdotpath/
		fi
	done
}

initZsh
