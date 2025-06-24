#!/usr/bin/env zsh
# ============================================================================
# Zsh Core Functions
#
# This file contains essential functions for Zsh module loading and compilation.
# These functions are used by the main .zshrc to efficiently load and compile
# other Zsh configuration modules.
#
# Functions:
# - zcompare: Check if a .zsh file needs recompilation to .zwc
# - load: Load and compile Zsh modules from ZMODDIR
# ============================================================================

function zcompare() {
  if [[ -s ${1} && (! -s ${1}.zwc || ${1} -nt ${1}.zwc) ]]; then
    echo "recompile: ${1}"
    zcompile ${1}
  fi
}

function load() {
  lib=${1:?"You have to specify a library file."}
  if [[ -f "$lib" ]]; then
    zcompare $lib
    . $lib
  fi
}
