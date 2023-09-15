#!/bin/bash

# @see https://wiki.archlinux.jp/index.php/XDG_Base_Directory
export XDG_CONFIG_HOME=$HOME/.config
export STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml
export DOTPATH=$HOME/src/github.com/paveg/dots
export ZDOTPATH="$DOTPATH/zsh.d"
export ZMODPATH="$ZDOTPATH/mods"

gitpath=$XDG_CONFIG_HOME/git
zdotpath=$XDG_CONFIG_HOME/zsh
nvimpath=$XDG_CONFIG_HOME/nvim

# Loading utils library
# shellcheck source=/dev/null
source "$ZMODPATH/util.zsh"
ln -sf "$DOTPATH/starship.toml" "$STARSHIP_CONFIG"


[ -d $zdotpath ] && mkdir -p $zdotpath
zdirs=$(find $ZDOTPATH/.z* -maxdepth 0 -type f)
ln -snfv "$DOTPATH/.zshenv" "$HOME/.zshenv"
for f in $zdirs; do
	fn=$(basename "$f")
	ln -snfv "$ZDOTPATH/$fn" "$zdotpath/$fn"
done
log_info "Completed initializing zshell..."


dirs=$(find $DOTPATH/* -maxdepth 0 -type d)
for d in $dirs; do
	name=$(basename "$d")
	[ $name = "fzf" ] && continue
	[ $name = "git" ] && ln -snfv "$DOTPATH/git" "$gitpath"
	[ $name = "nvim" ] && ln -snfv "$DOTPATH/nvim" "$nvimpath"
done
log_info "Completed initializing .config..."

log_pass "Completed initializing dots 🎉"
