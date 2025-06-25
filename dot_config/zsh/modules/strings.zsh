#!/usr/bin/env zsh
# ============================================================================
# String Manipulation Utilities
#
# This module provides string manipulation and text processing functions.
#
# Functions:
# - copy_str, lower, upper
# ============================================================================

copy_str() {
  if [[ $# -eq 0 ]]; then
    cat <&0
  elif [[ $# -eq 1 ]]; then
    if [[ -f "$1" ]] && [[ -r "$1" ]]; then
      cat "$1"
    else
      echo "$1"
    fi
  else
    return 1
  fi
}

# lower returns a copy of the string with all letters mapped to their lower case.
lower() { # shellcheck disable=SC2120
  copy_str | tr "[:upper:]" "[:lower:]"
}

# upper returns a copy of the string with all letters mapped to their upper case.
upper() { # shellcheck disable=SC2120
  copy_str | tr "[:lower:]" "[:upper:]"
}
