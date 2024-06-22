#!/bin/bash

# Initial settings
export GHQ_ROOT=$HOME/src
export GITHUB_USER=paveg
export GITHUB_REPO=dotfiles
export DOT_PATH=$GHQ_ROOT/github.com/$GITHUB_USER/$GITHUB_REPO
export ZSH_PATH=$DOT_PATH/zsh.d

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

ln -sfv $ZSH_PATH/.zshenv $HOME/.zshenv
ln -sfv $ZSH_PATH/.zshrc $HOME/.zshrc
ln -sfv $ZSH_PATH/.zprofile $HOME/.zprofile

ln -sfnv $DOT_PATH/git $XDG_CONFIG_HOME/git
