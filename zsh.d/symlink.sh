#!/bin/bash

basepath=$(
	cd $(dirname $0)
	pwd
)

xdgpath=$HOME/.config
zdotpath=$xdgpath/zsh

function initZsh() {
	log_info "Start to initialize zsh"
	if [ ! -d "$zdotpath" ]; then
		mkdir "$zdotpath"
	fi

	for zfile in zsh.d/.*; do
		file=$(dirname "$zfile")
		if [[ ! -d "$zfile" && $file != "symlink.sh" && $file != "." && $file != ".." && $file != ".git" ]]; then
			is_debug && log_pass "Symlink $basepath/$zfile to $zdotpath/"
			ln -sf "$basepath/$zfile" "$zdotpath/"
		fi
	done
	log_pass "Initialization zsh successfully!"
}

initZsh
