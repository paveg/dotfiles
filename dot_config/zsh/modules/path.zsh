#!/usr/bin/env zsh
# ============================================================================
# PATH Management and Utilities
#
# This module manages PATH configuration for development tools and provides
# debugging utilities.
#
# Functions:
# - path_prepend: Safely prepend to PATH (avoiding duplicates)
# - path_append: Safely append to PATH (avoiding duplicates)
# - path_show: Display current PATH entries
# - path_clean: Remove duplicate PATH entries
# - path_check: Check if PATH contains expected development tools
# ============================================================================

# Ensure XDG directories are set
: ${XDG_DATA_HOME:="$HOME/.local/share"}
: ${XDG_CONFIG_HOME:="$HOME/.config"}

# Safely prepend directory to PATH (if exists and not already in PATH)
path_prepend() {
  local dir="$1"
  if [[ -d "$dir" && ":$PATH:" != *":$dir:"* ]]; then
    export PATH="$dir:$PATH"
  fi
}

# Safely append directory to PATH (if exists and not already in PATH)
path_append() {
  local dir="$1"
  if [[ -d "$dir" && ":$PATH:" != *":$dir:"* ]]; then
    export PATH="$PATH:$dir"
  fi
}

# Configure development tool paths
# This is sourced early in .zshenv for consistent PATH across all shell types

# User local binaries (highest priority)
path_prepend "$HOME/.local/bin"
path_prepend "$HOME/bin"

# Language-specific paths (in priority order)
# Rust/Cargo
[[ -d "$HOME/.cargo/bin" ]] && path_prepend "$HOME/.cargo/bin"

# Go
if [[ -n "$GOPATH" ]]; then
  path_prepend "$GOPATH/bin"
elif [[ -d "$HOME/go/bin" ]]; then
  path_prepend "$HOME/go/bin"
fi

# Node.js package managers
[[ -n "$PNPM_HOME" ]] && path_prepend "$PNPM_HOME"
[[ -d "$HOME/.yarn/bin" ]] && path_prepend "$HOME/.yarn/bin"

# Python
[[ -d "$HOME/.rye/shims" ]] && path_prepend "$HOME/.rye/shims"

# Ruby
[[ -d "$HOME/.rbenv/shims" ]] && path_prepend "$HOME/.rbenv/shims"

# Homebrew (already set in .zshenv, but ensure it's there)
{{- if eq .chezmoi.os "darwin" }}
if [[ "{{ .chezmoi.arch }}" == "arm64" ]]; then
  path_prepend "/opt/homebrew/bin"
  path_prepend "/opt/homebrew/sbin"
else
  path_prepend "/usr/local/bin"
  path_prepend "/usr/local/sbin"
fi
{{- end }}

# mise shims (if mise is being used)
[[ -d "$XDG_DATA_HOME/mise/shims" ]] && path_prepend "$XDG_DATA_HOME/mise/shims"

# Show current PATH entries in a readable format
path_show() {
  echo "Current PATH entries ($(echo $PATH | tr ':' '\n' | wc -l | tr -d ' ') total):"
  echo $PATH | tr ':' '\n' | nl
}

# Clean duplicate PATH entries
path_clean() {
  export PATH=$(echo $PATH | tr ':' '\n' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//')
  echo "PATH cleaned. New entry count: $(echo $PATH | tr ':' '\n' | wc -l | tr -d ' ')"
}

# Check if PATH contains expected development tools
path_check() {
  echo "Checking development tool availability in PATH:"

  local tools=(
    "brew:/opt/homebrew/bin"
    "cargo:$HOME/.cargo/bin"
    "go:$GOBIN"
    "pnpm:$PNPM_HOME"
    "yarn:$HOME/.yarn/bin"
  )

  for tool_info in $tools; do
    local tool=${tool_info%%:*}
    local expected_path=${tool_info#*:}

    if command -v $tool >/dev/null 2>&1; then
      local actual_path=$(command -v $tool)
      echo "✓ $tool: $actual_path"
      if [[ "$actual_path" == "$expected_path/$tool" ]]; then
        echo "  → Correctly found in expected path"
      else
        echo "  → Found in different path (expected: $expected_path)"
      fi
    else
      echo "✗ $tool: not found"
    fi
    echo
  done
}
