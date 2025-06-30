#!/usr/bin/env zsh
# ============================================================================
# Zsh Module System Initialization
#
# This file initializes the enhanced module system with dependency resolution
# and categorized module loading. It replaces the simple module loading logic
# with intelligent dependency management.
#
# Usage:
#   source "$XDG_CONFIG_HOME/zsh/init.zsh"
#
# Environment Variables:
#   DOTS_DEBUG=1         Enable debug output
#   DOTS_SKIP_MODULES    Comma-separated list of modules to skip
#   DOTS_ONLY_MODULES    Comma-separated list of modules to load only
# ============================================================================

# Ensure we have required environment variables
: ${XDG_CONFIG_HOME:="$HOME/.config"}
: ${ZDOTDIR:="$XDG_CONFIG_HOME/zsh"}

# Module system configuration (only set if not already defined as readonly)
: ${ZMODDIR:="$ZDOTDIR/modules"}
typeset -g DOTS_DEBUG="${DOTS_DEBUG:-0}"

# Initialize module system
init_module_system() {
  local start_time="$(date +%s.%3N)"
  
  # Load the core metadata and loader system first
  local core_dir="$ZMODDIR/core"
  
  # Check if core directory exists
  if [[ ! -d "$core_dir" ]]; then
    # Fallback to legacy flat structure
    [[ "$DOTS_DEBUG" == "1" ]] && echo "Core directory not found, using legacy loading"
    load_legacy_modules
    return $?
  fi
  
  # Load metadata system (must be first)
  if [[ -f "$core_dir/metadata.zsh" ]]; then
    source "$core_dir/metadata.zsh"
  else
    echo "Error: metadata.zsh not found in core directory" >&2
    return 1
  fi
  
  # Load enhanced loader
  if [[ -f "$core_dir/loader.zsh" ]]; then
    source "$core_dir/loader.zsh"
  else
    echo "Error: loader.zsh not found in core directory" >&2
    return 1
  fi
  
  # Load modules in the new organized structure
  load_organized_modules
  
  local end_time="$(date +%s.%3N)"
  local total_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "unknown")
  
  [[ "$DOTS_DEBUG" == "1" ]] && echo "Module system initialized in ${total_time}s"
}

# Load modules from the organized directory structure
load_organized_modules() {
  local module_dir="$ZMODDIR"
  
  # Define loading order by category (critical for proper initialization)
  local category_order=(
    "core"          # Must be first: platform, terminal, path, core
    "config"        # Basic configuration
    "utils"         # Utility functions
    "ui"            # User interface
    "tools"         # Tool integrations
    "experimental"  # Optional experimental features
    "local"         # Local overrides (last)
  )
  
  [[ "$DOTS_DEBUG" == "1" ]] && echo "Loading modules from organized structure"
  
  # Process module filtering
  local skip_modules=()
  local only_modules=()
  
  if [[ -n "$DOTS_SKIP_MODULES" ]]; then
    skip_modules=(${(s:,:)DOTS_SKIP_MODULES})
    [[ "$DOTS_DEBUG" == "1" ]] && echo "Skipping modules: ${skip_modules[*]}"
  fi
  
  if [[ -n "$DOTS_ONLY_MODULES" ]]; then
    only_modules=(${(s:,:)DOTS_ONLY_MODULES})
    [[ "$DOTS_DEBUG" == "1" ]] && echo "Loading only modules: ${only_modules[*]}"
  fi
  
  # Load categories in order
  for category in "${category_order[@]}"; do
    local category_dir="$module_dir/$category"
    
    [[ ! -d "$category_dir" ]] && continue
    
    [[ "$DOTS_DEBUG" == "1" ]] && echo "Loading category: $category"
    
    # Special handling for core category (strict order required)
    if [[ "$category" == "core" ]]; then
      # Core modules must load in this exact order
      local core_order=(
        "metadata"    # Already loaded, but ensure it's marked
        "loader"      # Already loaded, but ensure it's marked  
        "platform"    # Must be first for is_exist_command
        "terminal"    # Early terminal setup
        "core"        # Essential functions
        "path"        # PATH management
      )
      
      for module_name in "${core_order[@]}"; do
        local module_file="$category_dir/$module_name.zsh"
        
        # Skip if already loaded (metadata and loader)
        if [[ "$module_name" == "metadata" ]] || [[ "$module_name" == "loader" ]]; then
          # Just mark as loaded if not already
          if [[ -z "${MODULE_METADATA[$module_name.loaded]}" ]]; then
            declare_module "$module_name" "category:core"
            mark_module_loaded "$module_name"
          fi
          continue
        fi
        
        # Apply filtering
        if should_skip_module "$module_name"; then
          continue
        fi
        
        if [[ -f "$module_file" ]]; then
          load_module "$module_file"
        fi
      done
    else
      # For other categories, use dependency-based loading
      load_modules_by_category "$category" "$module_dir"
    fi
  done
  
  # Load any remaining modules not in the standard categories
  for module_file in "$module_dir"/*.zsh(N); do
    local module_name="${module_file:t:r}"
    
    if should_skip_module "$module_name"; then
      continue
    fi
    
    if ! is_module_loaded "$module_name"; then
      [[ "$DOTS_DEBUG" == "1" ]] && echo "Loading uncategorized module: $module_name"
      load_module "$module_file"
    fi
  done
}

# Check if a module should be skipped based on filtering rules
should_skip_module() {
  local module_name="$1"
  
  # Check skip list
  if [[ -n "$DOTS_SKIP_MODULES" ]]; then
    local skip_modules=(${(s:,:)DOTS_SKIP_MODULES})
    for skip in "${skip_modules[@]}"; do
      if [[ "$module_name" == "$skip" ]]; then
        [[ "$DOTS_DEBUG" == "1" ]] && echo "Skipping module: $module_name"
        return 0  # Should skip
      fi
    done
  fi
  
  # Check only list (if specified)
  if [[ -n "$DOTS_ONLY_MODULES" ]]; then
    local only_modules=(${(s:,:)DOTS_ONLY_MODULES})
    for only in "${only_modules[@]}"; do
      if [[ "$module_name" == "$only" ]]; then
        return 1  # Should not skip
      fi
    done
    # Not in only list, so skip
    [[ "$DOTS_DEBUG" == "1" ]] && echo "Not in only list, skipping: $module_name"
    return 0
  fi
  
  return 1  # Should not skip
}

# Legacy module loading (fallback for old structure)
load_legacy_modules() {
  [[ "$DOTS_DEBUG" == "1" ]] && echo "Using legacy module loading"
  
  # Traditional loading order for backward compatibility
  local legacy_order=(
    "platform" "terminal" "core" "config" "alias" "func" "keybind" "plugin" "local"
  )
  
  for module_name in "${legacy_order[@]}"; do
    local module_file="$ZMODDIR/$module_name.zsh"
    
    if [[ -f "$module_file" ]]; then
      [[ "$DOTS_DEBUG" == "1" ]] && echo "Loading legacy module: $module_name"
      source "$module_file"
      
      # Compile for performance
      if (( $+functions[zcompare] )); then
        zcompare "$module_file"
      fi
    fi
  done
}

# Module management utilities for interactive use
alias module-list='list_modules'
alias module-info='show_module_info'
alias module-reload='reload_module'
alias module-validate='validate_modules'
alias module-debug='debug_modules'
alias module-graph='generate_dependency_graph'

# Performance monitoring
alias module-stats='get_loading_stats'

# Quick module category loading (for testing)
load_core_only() {
  DOTS_ONLY_MODULES="platform,terminal,core,path" init_module_system
}

load_minimal() {
  DOTS_ONLY_MODULES="platform,core,config" init_module_system
}

# Development helpers
reload_module_system() {
  echo "Reloading module system..."
  
  # Unload all modules
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.loaded ]]; then
      MODULE_METADATA[$key]="0"
    fi
  done
  
  # Clear metadata system
  unset MODULE_METADATA
  unset _MODULE_METADATA_INITIALIZED
  
  # Reload
  init_module_system
}

# Note: In zsh, functions are automatically available to subshells
# No need to export functions like in bash

# Initialize the module system
init_module_system