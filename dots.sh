#!/bin/bash

# @see https://wiki.archlinux.jp/index.php/XDG_Base_Directory
export XDG_CONFIG_HOME=$HOME/.config
export XDG_DATA_HOME=$HOME/.local/share
export CARGO_HOME=$XDG_DATA_HOME/cargo
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

unalias find 2>/dev/null

is_exist_command curl && is_exist_command git && is_exist_command zsh || {
	log_warn "Kindly install curl, git and zsh first."
	exit 1
}

is_exist_command asdf && log_info "asdf is already installed." || {
	git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.13.1
	# shellcheck source=/dev/null
	source "$HOME"/.asdf/asdf.sh
	log_pass "Completed installation asdf..."
}

is_exist_command direnv && log_info "direnv is already installed." || {
	asdf pluging-add direnv
	asdf install direnv latest
	log_pass "Completed installation direnv..."
}

is_exist_command go && log_info "Golang is already installed." || {
	asdf plugin-add golang
	asdf install golang latest
	log_pass "Completed installation Golang..."
}

is_exist_command ghq && log_info "ghq is already installed." || {
	go install github.com/x-motemen/ghq@latest
	log_pass "Completed installation ghq..."
}

# starship
is_exist_command starship && log_info "starship is already installed." || {
	curl -sS https://starship.rs/install.sh | sh
	ln -sf "$DOTPATH/starship.toml" "$STARSHIP_CONFIG"
	log_pass "Completed installation starship..."
}

# rustup
is_exist_command rustup && log_info "rustup is already installed." || {
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
	# shellcheck source=/dev/null
	source "$CARGO_HOME"/env
	log_pass "Completed installation rustup..."
}

[ ! -d "$zdotpath" ] && mkdir -p "$zdotpath"
zdirs=$(find "$ZDOTPATH"/.z* -maxdepth 0 -type f)
ln -snf "$DOTPATH/.zshenv" "$HOME/.zshenv"
for f in $zdirs; do
	fn=$(basename "$f")
	ln -snf "$ZDOTPATH/$fn" "$zdotpath/$fn"
done
log_info "Completed initializing zshell..."

dirs=$(find "$DOTPATH"/* -maxdepth 0 -type d)
for d in $dirs; do
	name=$(basename "$d")
	[ "$name" = "fzf" ] && continue
	[ "$name" = "git" ] && ln -snfv "$DOTPATH/git" "$gitpath"
	[ "$name" = "nvim" ] && ln -snfv "$DOTPATH/nvim" "$nvimpath"
	[ "$name" = "alacritty" ] && ln -snfv "$DOTPATH/alacritty" "$XDG_CONFIG_HOME"/alacritty
	[ "$name" = "fonts" ] && {
		is_osx && cp -r "$DOTPATH/fonts/." "$HOME/Library/Fonts/"
	}
	[ "$name" = "zellij" ] && ln -snfv "$DOTPATH/zellij" "$XDG_CONFIG_HOME"/zellij
done

log_info "Completed initializing .config..."

log_info "Start installing rust tools..."

cargo install --locked ripgrep bat fd-find eza navi zellij

log_pass "Completed initializing dots 🎉"
