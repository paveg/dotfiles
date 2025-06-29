#!/usr/bin/env zsh
# ============================================================================
# Terminal Detection and Configuration
#
# This module handles terminal-specific configurations and fixes issues with
# terminal detection, particularly for alacritty and other modern terminals.
#
# Must be loaded early to ensure proper terminal setup before other modules.
# ============================================================================

# Fix for alacritty terminal detection
# Alacritty sets TERM=alacritty but some systems don't have proper terminfo
if [[ "$TERM" == "alacritty" ]]; then
  # Check if alacritty terminfo exists
  if ! infocmp alacritty &>/dev/null; then
    # Fallback to xterm-256color which is widely supported
    export TERM="xterm-256color"
  fi
fi

# Ensure terminfo is properly set for color support
# This helps prevent tput errors
if [[ -z "$TERMINFO" ]] && [[ -d "$HOME/.terminfo" ]]; then
  export TERMINFO="$HOME/.terminfo"
fi

# Set color capability for terminals that support it
# This helps zinit and plugins detect color support properly
if [[ "$TERM" != "dumb" ]]; then
  # Use zsh's built-in color support instead of tput
  autoload -Uz colors && colors
  
  # Export color support for tools that check these
  export COLORTERM="${COLORTERM:-truecolor}"
  export CLICOLOR=1
fi

# Function to safely use tput with fallback
safe_tput() {
  local cmd="$1"
  shift
  
  # Check if tput is available and terminal is not dumb
  if command -v tput >/dev/null 2>&1 && [[ "$TERM" != "dumb" ]]; then
    # Try to execute tput, but suppress errors
    tput "$cmd" "$@" 2>/dev/null || true
  fi
}

# Note: Function is available in current shell context
# Export removed to prevent startup output
