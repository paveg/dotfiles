localconf=$HOME/.zshrc.local.zsh
if [[ -f $localconf ]]; then
  log_info "Found local config."
  load $localconf
else
  log_info "Not found local configurations."
fi
