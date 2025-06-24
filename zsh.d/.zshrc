# This is a profiling zshrc setting, set ZSHRC_PROFILE envvar to any value if you need.
if [ "$ZSHRC_PROFILE" != "" ]; then
  zmodload zsh/zprof && zprof >/dev/null
fi

# Ensure ZMODDIR is set (fallback if .zshenv wasn't sourced)
: ${ZMODDIR:="$HOME/repos/github.com/paveg/dotfiles/zsh.d/modules"}

# Define essential functions directly to ensure availability
function zcompare() {
  [[ -s ${1} && (! -s ${1}.zwc || ${1} -nt ${1}.zwc) ]] || return 1
  zcompile ${1} 2>/dev/null
}

function load() {
  local lib=${1:?"Library file required"}
  [[ -f "$lib" ]] || return 1
  zcompare "$lib"
  source "$lib"
}

function init_completion() {
  [[ -n "$_COMP_INITIALIZED" ]] && return 0
  local comp_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
  [[ -d "$comp_cache_dir" ]] || mkdir -p "$comp_cache_dir"
  local comp_dump="$comp_cache_dir/zcompdump"
  autoload -Uz compinit
  if [[ ! -f "$comp_dump" || "$comp_dump" -ot ~/.zshrc ]]; then
    compinit -d "$comp_dump"
  else
    compinit -C -d "$comp_dump"
  fi
  export _COMP_INITIALIZED=1
}

# Initialize completion system early
init_completion

# Load essential modules first (required by others)
load $ZMODDIR/platform.zsh
load $ZMODDIR/logging.zsh
load $ZMODDIR/strings.zsh

# Load remaining modules (optimized loop)
for module in config plugin func keybind alias; do
  load $ZMODDIR/$module.zsh
  [[ -z "$ZSHRC_PROFILE" ]] && command -v log_pass >/dev/null && log_pass "Loading completed $module.zsh"
done

# Load local configuration if exists
localconf=$HOME/.zshrc.local.zsh
if [[ -f $localconf ]]; then
  [[ -z "$ZSHRC_PROFILE" ]] && command -v log_info >/dev/null && log_info "Found local configuration file: $localconf"
  load $localconf
  [[ -z "$ZSHRC_PROFILE" ]] && command -v log_pass >/dev/null && log_pass "Loading completed $(basename $localconf)"
fi

# ============================================================================
# Tool Initialization (Performance Optimized)
# ============================================================================

# Fast tools - initialize immediately
eval "$(starship init zsh)" # Prompt must be initialized for display

# Conditional tool initialization
command -v fzf >/dev/null && source <(fzf --zsh)
[[ -f "$XDG_CONFIG_HOME/broot/launcher/bash/br" ]] && source "$XDG_CONFIG_HOME/broot/launcher/bash/br"

# Tool initialization - smart approach for performance and reliability
# mise: Conditional initialization based on shell context
if command -v mise >/dev/null; then
  # If in tmux, zellij (session active), or nested shell (SHLVL > 2), initialize immediately for consistency
  # Otherwise use lazy loading for faster startup
  if [[ -n "$TMUX" ]] || [[ -n "$ZELLIJ" && "$ZELLIJ" != "0" ]] || [[ "${SHLVL:-1}" -gt 2 ]]; then
    eval "$(mise activate zsh)"
  else
    # Lazy loading for main shell startup performance
    _lazy_mise() {
      local args=("$@")
      unfunction _lazy_mise mise
      eval "$(mise activate zsh)"
      mise "${args[@]}"
    }
    function mise() { _lazy_mise "$@" }
  fi
fi

# atuin: Keep lazy loading (less critical for cross-session consistency)
if command -v atuin >/dev/null; then
  _lazy_atuin() {
    unfunction _lazy_atuin atuin
    eval "$(atuin init zsh)"
    atuin "$@"
  }
  function atuin() { _lazy_atuin "$@" }
fi

# fpath for completions (PATH already handled in .zshenv)
typeset -U fpath
