#!/usr/bin/env zsh
# ============================================================================
# Terminal Detection and Configuration
#
# This module handles terminal-specific configurations and fixes issues with
# terminal detection, particularly for alacritty and other modern terminals.
#
# Must be loaded early to ensure proper terminal setup before other modules.
# ============================================================================

# Module metadata declaration
declare_module "terminal" \
    "depends:platform" \
    "category:core" \
    "description:Terminal detection and configuration for modern terminals" \
    "provides:safe_tput,COLORTERM,CLICOLOR" \
    "external:tput,infocmp" \
    "optional:tput,infocmp"

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

# Auto-start zellij for interactive shells
# Only in terminal environments, not in IDEs or CI
auto_start_zellij() {
    # Skip if already in zellij
    [[ -n "$ZELLIJ" ]] && return 0

    # Skip for non-interactive shells
    [[ ! -o interactive ]] && return 0

    # Skip in CI/automated environments
    [[ -n "$CI" || -n "$GITHUB_ACTIONS" || -n "$GITLAB_CI" ]] && return 0

    # Skip if explicitly disabled
    [[ "$DISABLE_AUTO_ZELLIJ" == "1" ]] && return 0
    [[ "$DISABLE_MULTIPLEXER" == "1" ]] && return 0

    # Only for alacritty or if explicitly enabled
    if [[ "$TERM_PROGRAM" == "Alacritty" ]] || [[ -n "$ALACRITTY_SOCKET" ]] || [[ "$AUTO_ZELLIJ" == "1" ]]; then
        if command -v zellij >/dev/null 2>&1; then
            exec zellij attach --index 0 --create
        fi
    fi
}

# Defer zellij auto-start until after all modules are loaded
# This ensures local.zsh settings are available
if [[ -o interactive ]]; then
    # Use precmd to start zellij after all initialization is complete
    _zellij_auto_start() {
        auto_start_zellij
        # Remove this hook after first execution
        precmd_functions=(${precmd_functions[@]:#_zellij_auto_start})
    }
    precmd_functions+=(_zellij_auto_start)
fi
