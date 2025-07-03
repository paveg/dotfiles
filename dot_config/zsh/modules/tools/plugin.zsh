#!/usr/bin/env zsh
# ============================================================================
# Zsh Plugin Management (Performance Optimized)
#
# This file manages Zsh plugins using zinit with aggressive performance tuning.
#
# Key optimizations:
# - Delayed loading with turbo mode for all plugins
# - Minimal completion system integration
# - Reduced plugin overhead
# - Async plugin loading where possible
# - Strategic wait times to prevent startup blocking
#
# Commands:
# - `zinit update` : Update all plugins
# - `zinit delete <plugin>` : Remove a plugin
# - `zinit list` : List installed plugins
# - `zinit times` : Show plugin loading times
# ============================================================================

# Module metadata declaration (only if function exists)
if (( $+functions[declare_module] )); then
  declare_module "plugin" \
    "depends:platform,core" \
    "category:tools" \
    "description:Zsh plugin management with performance optimization" \
    "provides:ZINIT_HOME" \
    "external:git" \
    "optional:"
fi

# Initialize zinit (optimized)
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Fast zinit installation check with error handling
if [[ ! -d $ZINIT_HOME/.git ]]; then
  debug "Installing zinit plugin manager..."
  [[ ! -d $ZINIT_HOME ]] && mkdir -p "$(dirname $ZINIT_HOME)"

  git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" || {
    error "Failed to install zinit"
    warn "Please install zinit manually or check your internet connection"
    return 1
  }
  debug "✓ Zinit installed successfully"
fi

# Configure zinit for better terminal compatibility
# Disable color output if terminal doesn't support it properly
if [[ "$TERM" == "dumb" ]] || ! command -v tput >/dev/null 2>&1; then
  typeset -g ZINIT[NO_COLOR]=1
fi

# Load zinit with error handling
if [[ -f "${ZINIT_HOME}/zinit.zsh" ]]; then
  source "${ZINIT_HOME}/zinit.zsh" || {
    error "Failed to load zinit"
    return 1
  }
else
  error "Zinit not found at ${ZINIT_HOME}/zinit.zsh"
  warn "Please reinstall zinit or check your installation"
  return 1
fi

# ============================================================================
# Core Plugins (Essential for Shell Experience)
# Tier 1: 0-20ms Critical (wait"2-3")
# ============================================================================

# 1. Fast syntax highlighting (wait"2" for immediate feedback while not blocking startup)
zinit ice wait"2" lucid atinit"ZINIT[COMPINIT_OPTS]=-C; zpcompinit; zpcdreplay"
zinit light zdharma/fast-syntax-highlighting

# 2. Additional completions (wait"2" for tab completion)
zinit ice wait"2" lucid blockf atpull"zinit creinstall -q ."
zinit light zsh-users/zsh-completions

# 3. Auto-suggestions (wait"3" for performance)
zinit ice wait"3" lucid atload"_zsh_autosuggest_start"
zinit light zsh-users/zsh-autosuggestions

# 4. Directory jumping with frecency (wait"3")
zinit ice wait"3" lucid
zinit light agkozak/zsh-z

# 5. History substring search (wait"3")
zinit ice wait"3" lucid
zinit light zsh-users/zsh-history-substring-search

# ============================================================================
# Productivity Enhancements
# Tier 2: 20-50ms User Functionality (wait"4-6")
# ============================================================================

# Remind about aliases you've defined
# NOTE: Temporarily disabled due to tput errors with alacritty
# zinit ice wait"5" lucid
# zinit light MichaelAquilina/zsh-you-should-use

# Auto-close brackets and quotes
zinit ice wait"4" lucid
zinit light hlissner/zsh-autopair

# Enhanced tab completion with fzf
zinit ice wait"4" lucid
zinit light Aloxaf/fzf-tab

# Interactive git operations with fzf
zinit ice wait"5" lucid
zinit light wfxr/forgit

# Fish-like abbreviations (expand shortcuts)
zinit ice wait"6" lucid
zinit light olets/zsh-abbr

# Per-directory history
zinit ice wait"6" lucid
zinit light jimhester/per-directory-history

# ============================================================================
# Completion snippets (external)
# Tier 3: 50-80ms Enhanced Features (wait"8-12")
# ============================================================================

# Docker completion (heavy, context-aware via lazy loading)
zinit ice wait"10" lucid as"completion"
zinit snippet https://github.com/docker/cli/blob/master/contrib/completion/zsh/_docker

# Docker Compose completion
zinit ice wait"10" lucid as"completion"
zinit snippet "https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/docker-compose/_docker-compose"

# ghq completion (lightweight utility)
zinit ice wait"8" lucid as"completion"
zinit snippet https://github.com/x-motemen/ghq/blob/master/misc/zsh/_ghq

# fd completion (commonly used)
zinit ice wait"8" lucid as"completion"
zinit snippet https://github.com/sharkdp/fd/blob/master/contrib/completion/_fd

# eza completion (commonly used)
zinit ice wait"8" lucid as"completion"
zinit snippet https://github.com/eza-community/eza/blob/main/completions/zsh/_eza

# ============================================================================
# Tool Completions (Dynamic)
# Performance-optimized based on usage patterns
# ============================================================================

# mise - enhanced lazy loading handles this more efficiently
# Delayed to allow enhanced_lazy_tools to initialize first
zinit ice wait"12" lucid atload"command -v mise >/dev/null && eval \"\$(mise completion zsh)\""
zinit light zdharma-continuum/null

# chezmoi - commonly used, medium priority
zinit ice wait"8" lucid atload"command -v chezmoi >/dev/null && eval \"\$(chezmoi completion zsh)\""
zinit light zdharma-continuum/null

# pnpm - project-specific, handled by lazy loading when in Node.js projects
zinit ice wait"10" lucid atload"command -v pnpm >/dev/null && eval \"\$(pnpm completion zsh)\""
zinit light zdharma-continuum/null

# gh - frequently used, higher priority
zinit ice wait"6" lucid atload"command -v gh >/dev/null && eval \"\$(gh completion -s zsh)\""
zinit light zdharma-continuum/null

# atuin - shell history management
if is_exist_command atuin; then
  # Debug output
  [[ "$DOTS_DEBUG" == "1" ]] && echo "Initializing atuin history management"
  
  # Load required zsh hook functionality
  autoload -U add-zsh-hook
  
  # Initialize atuin synchronously to avoid binding conflicts
  eval "$(atuin init zsh)"
  
  # Verify hooks are registered
  if [[ " ${preexec_functions[@]} " != *" _atuin_preexec "* ]]; then
    [[ "$DOTS_DEBUG" == "1" ]] && echo "Warning: atuin preexec hook not registered"
  else
    [[ "$DOTS_DEBUG" == "1" ]] && echo "✓ atuin hooks registered successfully"
  fi
  if [[ " ${precmd_functions[@]} " != *" _atuin_precmd "* ]]; then
    [[ "$DOTS_DEBUG" == "1" ]] && echo "Warning: atuin precmd hook not registered"
  fi
else
  [[ "$DOTS_DEBUG" == "1" ]] && echo "atuin not found, skipping initialization"
fi

# ============================================================================
# Heavy Completions (Context-aware and expensive)
# Tier 3: 50-80ms+ Enhanced Features (wait"10-12")
# ============================================================================

# Kubernetes - very expensive completion, context-aware via lazy loading
zinit ice wait"12" lucid atload"command -v kubectl >/dev/null && eval \"\$(kubectl completion zsh)\""
zinit light zdharma-continuum/null

# Rust toolchain - project-specific, lower frequency
zinit ice wait"10" lucid atload"command -v rustup >/dev/null && eval \"\$(rustup completions zsh)\""
zinit light zdharma-continuum/null

# just (Rust-based task runner) - project-specific
zinit ice wait"10" lucid atload"command -v just >/dev/null && eval \"\$(just --completions zsh)\""
zinit light zdharma-continuum/null

# Deno - less commonly used
zinit ice wait"11" lucid atload"command -v deno >/dev/null && eval \"\$(deno completions zsh)\""
zinit light zdharma-continuum/null

# ============================================================================
# Completion Styling and Configuration
# ============================================================================

# Case insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# Use cache for completions
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache"

# Group completions by type
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'

# Better file completion
zstyle ':completion:*' file-sort modification
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# fzf-tab configuration (if installed)
if (( $+functions[enable-fzf-tab] )); then
  # Preview directories
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null || ls -1 $realpath'

  # Preview files
  zstyle ':fzf-tab:complete:*:*' fzf-preview 'bat --color=always --style=numbers --line-range=:500 $realpath 2>/dev/null || cat $realpath 2>/dev/null || echo "Binary file"'
fi

# Performance note: All other completion optimizations are handled in core.zsh
# through the init_completion() function which coordinates with zinit

# Plugin loading completed
