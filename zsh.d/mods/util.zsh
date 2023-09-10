#!/bin/zsh -e

## Utilities

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

is_logging_pass() {
  if [[ "${ENABLE_LOGGING_PASS:-1}" = 1 ]]; then
    return 0
  else
    return 1
  fi
}

is_logging_info() {
  if [[ "${ENABLE_LOGGING_INFO:-0}" = 0 ]]; then
    return 0
  else
    return 1
  fi
}

logging() {
  if [[ "$#" -eq 0 ]] || [[ "$#" -gt 2 ]]; then
    echo "Usage: logging <fmt> <msg>"
    echo "Formatting Options:"
    echo "  TITLE, ERROR, WARN, INFO, SUCCESS"
    return 1
  fi

  local color=
  local text="$2"

  case "$1" in
  TITLE)
    color=yellow
    ;;
  ERROR | WARN)
    color=red
    ;;
  INFO)
    color=blue
    ;;
  SUCCESS)
    color=green
    ;;
  *)
    text="$1"
    ;;
  esac

  timestamp() {
    ink gray "["
    ink purple "$(date +%H:%M:%S)"
    ink gray "] "
  }

  timestamp
  ink "$color" "$text"
  echo
}

log_pass() {
  if is_logging_pass; then
    logging SUCCESS "$1"
  fi
}

log_fail() {
  logging ERROR "$1" 1>&2
}

log_warn() {
  logging WARN "$1"
}

log_info() {
  if is_logging_info; then
    logging INFO "$1"
  fi
}

log_echo() {
  logging TITLE "$1"
}

ink() {
  if [[ "$#" -eq 0 ]] || [[ "$#" -gt 2 ]]; then
    echo "Usage: ink <color> <text>"
    echo "Colors:"
    echo "  black, white, red, green, yellow, blue, purple, cyan, gray"
    return 1
  fi

  local open="\033["
  local close="${open}0m"
  local black="0;30m"
  local red="1;31m"
  local green="1;32m"
  local yellow="1;33m"
  local blue="1;34m"
  local purple="1;35m"
  local cyan="1;36m"
  local gray="0;37m"
  local white="$close"

  local text="$1"
  local color="$close"

  if [[ "$#" -eq 2 ]]; then
    text="$2"
    case "$1" in black | red | green | yellow | blue | purple | cyan | gray | white)
      eval color="\$$1"
      ;;
    esac
  fi

  printf "${open}${color}${text}${close}"
}

# is_debug returns true if $DOTS_DEBUG is set
is_debug() {
  if [[ "${DOTS_DEBUG:-0}" = 1 ]]; then
    return 0
  else
    return 1
  fi
}

is_exist_command() { command -v "$1" >/dev/null 2>&1; }
