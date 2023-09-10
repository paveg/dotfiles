localconf=$HOME/.zshrc.local.zsh
if [[ -f $localconf ]]; then
  load $localconf
else
  log_info "Not found local configurations."
fi
