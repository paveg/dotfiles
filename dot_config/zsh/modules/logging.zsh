#!/usr/bin/env zsh
# ============================================================================
# Logging and Color Utilities
#
# This module provides colored logging functionality used throughout
# the dotfiles loading process.
#
# Functions:
# - log_pass, log_fail, log_warn, log_info, log_echo
# - ink (color output)
# - logging (main logging function)
# ============================================================================

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
