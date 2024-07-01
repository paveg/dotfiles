#!/bin/bash

# Initial settings
export GHQ_ROOT=$HOME/repos
export GITHUB_USER=paveg
export GITHUB_REPO=dotfiles
export DOTDIR=$GHQ_ROOT/github.com/$GITHUB_USER/$GITHUB_REPO
export ZDOTDIR=$DOTDIR/zsh.d
export ZMODDIR=$ZDOTDIR/modules

export GLOBAL_BREWFILE_PATH=$HOME/.Brewfile

source $ZMODDIR/utils.zsh

log_info "Start installation"

is_exist_command brew || {
  log_fail "Homebrew is not installed"
  exit 1
}
if [[ -z $BUSINESS_USE ]]; then
  ln -sfnv $DOTDIR/homebrew/Brewfile $GLOBAL_BREWFILE_PATH
else
  ln -sfnv $DOTDIR/homebrew/Brewfile.work $GLOBAL_BREWFILE_PATH
fi

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Installation fonts
is_osx && cp -r $DOTDIR/fonts/* $HOME/Library/Fonts

ln -sfnv $ZDOTDIR/.zshenv $HOME/.zshenv
ln -sfnv $ZDOTDIR/.zshrc $HOME/.zshrc
ln -sfnv $ZDOTDIR/.zprofile $HOME/.zprofile

ln -sfnv $DOTDIR/git $XDG_CONFIG_HOME/git

# Environment variables
ln -sfnv $DOTDIR/.env.1password $HOME/.env.1password

# Brilliant command prompt
ln -sfn $DOTDIR/starship.toml $XDG_CONFIG_HOME/starship.toml

# Alacritty
ln -sfn $DOTDIR/alacritty $XDG_CONFIG_HOME/alacritty

# zellij
ln -snf $DOTDIR/zellij $XDG_CONFIG_HOME/zellij

# neovim
ln -snfv $DOTDIR/nvim $XDG_CONFIG_HOME/nvim

# lazygit
ln -sfnv $DOTDIR/lazygit $XDG_CONFIG_HOME/lazygit

# zeno
ln -sfnv $DOTDIR/zeno $XDG_CONFIG_HOME/zeno

log_pass "Installation completed"
