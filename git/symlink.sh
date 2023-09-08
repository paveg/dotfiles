#!/bin/bash

basepath=$(cd $(dirname $0);pwd)
xdgpath=$HOME/.config
gitpath=$xdgpath/git

function initGitConfig () {
  echo "[info] Initialize git config"
  if [ ! -d $gitpath ]; then
    mkdir $gitpath
  fi

  for gitfile in git/*
  do
    file=$(basename $gitfile)
    if [ ! -d $gitfile -a $file != symlink.sh -a $file != "." -a $file != ".." -a $file != ".git" ]; then
      echo "Symlink $basepath/$gitfile to $gitpath/$file"
      ln -sf $basepath/$gitfile $gitpath/$file
    fi
  done
}

initGitConfig
