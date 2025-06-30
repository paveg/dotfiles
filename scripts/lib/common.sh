#!/usr/bin/env bash
# Common utilities for dotfiles scripts
# This file provides shared functions and variables used across multiple scripts

# Guard against double-sourcing
if [[ -n "${_DOTFILES_COMMON_SOURCED:-}" ]]; then
    return 0
fi
readonly _DOTFILES_COMMON_SOURCED=1

# Enable strict error handling
set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Print utility functions
print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Cleanup backup files created during script execution
# Usage: cleanup_backups [file_pattern]
# Example: cleanup_backups "*.bak"
cleanup_backups() {
    local pattern="${1:-*.bak}"
    local backup_count=0
    
    # Find and remove backup files
    while IFS= read -r -d '' backup_file; do
        if [[ -f "$backup_file" ]]; then
            rm -f "$backup_file"
            ((backup_count++))
        fi
    done < <(find . -name "$pattern" -type f -print0 2>/dev/null || true)
    
    if [[ $backup_count -gt 0 ]]; then
        print_info "Cleaned up $backup_count backup file(s)"
    fi
}

# Error handler for consistent error reporting
# Usage: Set up with: trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR
error_handler() {
    local exit_code=$1
    local line_number=$2
    local command=$3
    
    print_error "Command failed with exit code $exit_code at line $line_number: $command"
}

# Check if a command exists
# Usage: if command_exists "git"; then ... fi
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get the script directory (where the script is located)
# Usage: SCRIPT_DIR=$(get_script_dir)
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    local dir
    
    # Resolve symlinks
    while [[ -h "$source" ]]; do
        dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    echo "$dir"
}

# Ensure a directory exists, create if it doesn't
# Usage: ensure_dir "/path/to/directory"
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        print_info "Created directory: $dir"
    fi
}

# Export common variables that scripts might need
export DOTFILES_LIB_DIR="$(get_script_dir)"
export DOTFILES_SCRIPTS_DIR="$(dirname "$DOTFILES_LIB_DIR")"
export DOTFILES_ROOT="$(dirname "$DOTFILES_SCRIPTS_DIR")"