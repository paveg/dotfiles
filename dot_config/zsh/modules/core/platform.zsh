#!/usr/bin/env zsh
# ============================================================================
# Platform Detection and OS Utilities
#
# This module provides OS detection and platform-specific functionality.
# Must be loaded early as many other modules depend on these functions.
#
# Functions:
# - ostype, os_detect, is_osx, is_linux
# - is_exist_command (command existence checking)

# Module metadata declaration (will be called later when metadata system is loaded)
if (( $+functions[declare_module] )); then
    declare_module "platform" \
        "category:core" \
        "description:OS detection and command existence checking" \
        "provides:ostype,os_detect,is_osx,is_linux,is_exist_command,auto_tmux_linux,is_debug" \
        "external:uname,tmux"
fi
# ============================================================================

# ostype returns the lowercase OS name
ostype() { # shellcheck disable=SC2119
    uname | tr "[:upper:]" "[:lower:]"
}

# os_detect export the PLATFORM variable as you see fit
os_detect() {
    export PLATFORM
    case "$(ostype)" in
        *'linux'*) PLATFORM='linux' ;;
        *'darwin'*) PLATFORM='osx' ;;
        *) PLATFORM='unknown' ;;
    esac
}

# is_osx returns true if running OS is Macintosh
is_osx() {
    os_detect
    if [[ "$PLATFORM" = "osx" ]]; then
        return 0
    else
        return 1
    fi
}

# is_linux returns true if running OS is GNU/Linux
is_linux() {
    os_detect
    if [[ "$PLATFORM" = "linux" ]]; then
        return 0
    else
        return 1
    fi
}

is_exist_command() { command -v "$1" >/dev/null 2>&1; }

# Auto-start tmux on Linux systems (SSH/remote connections)
auto_tmux_linux() {
    # Only on Linux systems
    if ! is_linux; then
        return 0
    fi

    # Only if tmux is available
    if ! is_exist_command tmux; then
        return 0
    fi

    # Skip if already in tmux
    if [[ -n "$TMUX" ]]; then
        return 0
    fi

    # Skip if not interactive shell
    if [[ ! -o interactive ]]; then
        return 0
    fi

    # Skip if explicitly disabled
    if [[ "${DISABLE_AUTO_TMUX:-0}" = "1" ]]; then
        return 0
    fi

    # Skip if in certain contexts (CI, Docker, etc.)
    if [[ -n "$CI" ]] || [[ -n "$CONTAINER" ]] || [[ -f /.dockerenv ]]; then
        return 0
    fi

    # Only auto-start for SSH sessions or if explicitly requested
    if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]] || [[ "${AUTO_TMUX:-0}" = "1" ]]; then
        # Check if there are existing tmux sessions
        if tmux list-sessions &>/dev/null; then
            # Attach to existing session
            echo "🔄 Attaching to existing tmux session..."
            exec tmux attach-session
        else
            # Create new session
            echo "🚀 Starting new tmux session..."
            exec tmux new-session
        fi
    fi
}

# is_debug returns true if $DOTS_DEBUG is set
is_debug() {
    if [[ "${DOTS_DEBUG:-0}" = 1 ]]; then
        return 0
    else
        return 1
    fi
}
