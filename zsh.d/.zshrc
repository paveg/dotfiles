# This is a profiling zshrc setting, set ZSHRC_PROFILE envvar to any value if you need.
if [ "$ZSHRC_PROFILE" != "" ]; then
  zmodload zsh/zprof && zprof >/dev/null
fi

source $ZMODDIR/core.zsh

: "Loading modules" && {
  declare -ax load_paths=(
    # Essential utilities (split from utils.zsh for better organization)
    $ZMODDIR/platform.zsh # OS detection - required by many modules
    $ZMODDIR/logging.zsh  # Logging functions - required for progress messages
    $ZMODDIR/strings.zsh  # String utilities - standalone
    $ZMODDIR/config.zsh
    $ZMODDIR/plugin.zsh
    $ZMODDIR/func.zsh
    $ZMODDIR/keybind.zsh
    $ZMODDIR/alias.zsh
  )

  for load_path in ${load_paths[@]}; do
    load $load_path
    [[ -z "$ZSHRC_PROFILE" ]] && command -v log_pass >/dev/null && log_pass "Loading completed $(basename $load_path)"
  done

  # TODO: Rename to localconf.zsh
  localconf=$HOME/.zshrc.local.zsh
  if [[ -f $localconf ]]; then
    [[ -z "$ZSHRC_PROFILE" ]] && command -v log_info >/dev/null && log_info "Found local configuration file: $localconf"
    load $localconf
    [[ -z "$ZSHRC_PROFILE" ]] && command -v log_pass >/dev/null && log_pass "Loading completed $(basename $localconf)"
  fi
}

# ============================================================================
# Tool Initialization (Performance Optimized)
# ============================================================================

# Fast tools - initialize immediately
eval "$(starship init zsh)" # Prompt must be initialized for display

# Conditional tool initialization
is_exist_command fzf && source <(fzf --zsh)
[[ -f "$XDG_CONFIG_HOME/broot/launcher/bash/br" ]] && source "$XDG_CONFIG_HOME/broot/launcher/bash/br"

# Heavy tools - lazy load for better startup performance
_lazy_atuin() {
  unfunction _lazy_atuin
  eval "$(atuin init zsh)"
  atuin "$@"
}

_lazy_mise() {
  unfunction _lazy_mise  
  eval "$(mise activate zsh)"
  mise "$@"
}

# Set up lazy loading aliases
is_exist_command atuin && alias atuin="_lazy_atuin"
is_exist_command mise && alias mise="_lazy_mise"

# PATH optimization
typeset -U PATH fpath
[[ -d ~/.console-ninja/.bin ]] && PATH=~/.console-ninja/.bin:$PATH
