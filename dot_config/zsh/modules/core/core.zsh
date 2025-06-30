#!/usr/bin/env zsh
# ============================================================================
# Zsh Core Functions (Performance Optimized)
#
# This file contains essential functions for Zsh module loading and compilation.
# These functions are used by the main .zshrc to efficiently load and compile
# other Zsh configuration modules.
#
# Functions:
# - zcompare: Check if a .zsh file needs recompilation to .zwc

# Module metadata declaration
declare_module "core" \
    "depends:platform" \
    "category:core" \
    "description:Essential functions for module loading and compilation" \
    "provides:zcompare,load,init_completion,error,warn,debug,require_command,require_file,require_directory" \
    "external:zcompile,compinit"
# - load: Load and compile Zsh modules from ZMODDIR (optimized)
# - init_completion: Initialize completion system with caching
# - error/warn/debug: Standardized error reporting utilities
# - require_command: Validate command availability
# ============================================================================

# Guard against multiple loads - but always ensure functions are defined
if [[ -n "$_CORE_LOADED" ]]; then
    # Functions should already be defined, but verify
    [[ $(type -w load 2>/dev/null) ]] && [[ $(type -w init_completion 2>/dev/null) ]] && return 0
fi
export _CORE_LOADED=1

# Optimized compilation check
function zcompare() {
    [[ -s ${1} && (! -s ${1}.zwc || ${1} -nt ${1}.zwc) ]] || return 1
    zcompile ${1} 2>/dev/null
}

# Optimized module loading
function load() {
    local lib=${1:?"Library file required"}
    [[ -f "$lib" ]] || return 1
    zcompare "$lib"
    source "$lib"
}

# Initialize completion system with caching (replaces expensive compinit)
function init_completion() {
    # Skip if already initialized
    [[ -n "$_COMP_INITIALIZED" ]] && return 0

    # Cache directory for completion dumps
    local comp_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
    [[ -d "$comp_cache_dir" ]] || mkdir -p "$comp_cache_dir"

    local comp_dump="$comp_cache_dir/zcompdump"

    # Fast initialization using cached dump when possible
    autoload -Uz compinit
    if [[ ! -f "$comp_dump" || "$comp_dump" -ot ~/.zshrc ]]; then
        # Full initialization only when necessary
        compinit -d "$comp_dump"
    else
        # Skip security check for faster startup
        compinit -C -d "$comp_dump"
    fi

    export _COMP_INITIALIZED=1
}

# ============================================================================
# Error Handling Utilities
# ============================================================================

# Standardized error reporting
error() {
    echo "Error: $*" >&2
}

warn() {
    echo "Warning: $*" >&2
}

debug() {
    [[ -n "$ZSHRC_DEBUG" ]] && echo "Debug: $*" >&2
}

# Command availability validation
require_command() {
    local cmd="$1"
    local message="${2:-$cmd is required but not installed}"

    command -v "$cmd" >/dev/null || {
        error "$message"
        return 127
    }
}

# Validate file existence with custom error
require_file() {
    local file="$1"
    local message="${2:-File not found: $file}"

    [[ -f "$file" ]] || {
        error "$message"
        return 2
    }
}

# Validate directory existence with custom error
require_directory() {
    local dir="$1"
    local message="${2:-Directory not found: $dir}"

    [[ -d "$dir" ]] || {
        error "$message"
        return 2
    }
}
