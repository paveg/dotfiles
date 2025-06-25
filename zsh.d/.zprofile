# Load essential utilities for .zprofile
# Ensure ZMODDIR is set
: ${ZMODDIR:="$HOME/repos/github.com/paveg/dotfiles/zsh.d/modules"}

# Define load function for .zprofile
function load() {
  local lib=${1:?"Library file required"}
  [[ -f "$lib" ]] || return 1
  [[ -s ${lib} && (! -s ${lib}.zwc || ${lib} -nt ${lib}.zwc) ]] && zcompile ${lib} 2>/dev/null
  source "$lib"
}

load $ZMODDIR/platform.zsh
load $ZMODDIR/logging.zsh

if [[ ! -d $XDG_CONFIG_HOME/op/plugins ]]; then
  log_warn "1password plugins is not installed"
  log_info "Run 'op plugin init gh' to install 1password plugins"
fi

# 1password plugins (load only if exists)
if [[ -f $XDG_CONFIG_HOME/op/plugins.sh ]]; then
  source $XDG_CONFIG_HOME/op/plugins.sh
fi
