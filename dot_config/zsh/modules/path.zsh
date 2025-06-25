#!/usr/bin/env zsh
# ============================================================================
# PATH Utilities
#
# This module provides utilities for managing and debugging PATH configuration.
#
# Functions:
# - path_show: Display current PATH entries
# - path_clean: Remove duplicate PATH entries
# - path_check: Check if PATH contains expected development tools
# ============================================================================

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
