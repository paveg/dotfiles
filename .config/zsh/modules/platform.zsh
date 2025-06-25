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

# is_debug returns true if $DOTS_DEBUG is set
is_debug() {
  if [[ "${DOTS_DEBUG:-0}" = 1 ]]; then
    return 0
  else
    return 1
  fi
}
