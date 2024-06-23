#!/bin/bash

# Initial settings
export GHQ_ROOT=$HOME/repos
export GITHUB_USER=paveg
export GITHUB_REPO=dotfiles
export DOT_PATH=$GHQ_ROOT/github.com/$GITHUB_USER/$GITHUB_REPO
export ZSH_PATH=$DOT_PATH/zsh.d
export ZMOD_PATH=$ZSH_PATH/modules

export GLOBAL_BREWFILE_PATH=$HOME/.Brewfile

source $ZMOD_PATH/utils.zsh

log_info "Start installation"

is_exist_command brew || {
  log_fail "Homebrew is not installed"
  exit 1
}
if [[ -z $BUSINESS_USE ]]; then
  ln -sfnv $DOT_PATH/homebrew/Brewfile $GLOBAL_BREWFILE_PATH
else
  ln -sfnv $DOT_PATH/homebrew/Brewfile.work $GLOBAL_BREWFILE_PATH
fi

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Installation fonts
is_osx && cp -r $DOT_PATH/fonts/* $HOME/Library/Fonts

ln -sfnv $ZSH_PATH/.zshenv $HOME/.zshenv
ln -sfnv $ZSH_PATH/.zshrc $HOME/.zshrc
ln -sfnv $ZSH_PATH/.zprofile $HOME/.zprofile

ln -sfnv $DOT_PATH/git $XDG_CONFIG_HOME/git

# Environment variables
ln -sfnv $DOT_PATH/.env.1password $HOME/.env.1password

# Brilliant command prompt
ln -sfn $DOT_PATH/starship.toml $XDG_CONFIG_HOME/starship.toml

# Alacritty
ln -sfn $DOT_PATH/alacritty $XDG_CONFIG_HOME/alacritty

# zellij
ln -snf $DOT_PATH/zellij $XDG_CONFIG_HOME/zellij

# neovim
ln -snfv $DOT_PATH/nvim $XDG_CONFIG_HOME/nvim

# lazygit
ln -sfnv $DOT_PATH/lazygit $XDG_CONFIG_HOME/lazygit

log_pass "Installation completed"
