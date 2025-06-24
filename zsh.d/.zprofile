# Load essential utilities for .zprofile
source $ZMODDIR/core.zsh
source $ZMODDIR/platform.zsh
source $ZMODDIR/logging.zsh

if [[ ! -d $XDG_CONFIG_HOME/op/plugins ]]; then
  log_warn "1password plugins is not installed"
  log_info "Run 'op plugin init gh' to install 1password plugins"
fi

# 1password plugins
source $XDG_CONFIG_HOME/op/plugins.sh
