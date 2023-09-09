#!/bin/bash

basepath=$(
  cd $(dirname $0)
  pwd
)
xdgpath=$HOME/.config
gitpath=$xdgpath/git

function initGitConfig() {
  log_info "Start to Iiitialize git config"
  if [ ! -d "$gitpath" ]; then
    mkdir "$gitpath"
  fi

  for gitfile in git/*; do
    file=$(basename "$gitfile")
    if [[ ! -d $gitfile && $file != "symlink.sh" && $file != "." && $file != ".." && $file != ".git" ]]; then
      is_debug && log_pass "Symlink $basepath/$gitfile to $gitpath/$file"
      ln -sf "$basepath/$gitfile" "$gitpath/$file"
    fi
  done
  log_pass "Initialization git config successfully!"
}

initGitConfig
