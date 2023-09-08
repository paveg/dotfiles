#!/bin/bash

basepath=$(cd $(dirname $0);pwd)
xdgpath=$HOME/.config
gitpath=$xdgpath/git

function initGitConfig () {
  echo "[info] Initialize git config"
  if [ ! -d $gitpath ]; then
    mkdir $gitpath
  fi

  for gitfile in git/.*
  do
    if [ ! -d $gitfile -a $gitfile != "." -a $gitfile != ".." -a $gitfile != ".git" ]; then
      echo "Symlink $basepath/$gitfile to $gitpath/"
    fi
  done
}

initGitConfig
