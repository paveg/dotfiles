#!/usr/bin/env zsh
# Module Metadata System
# This file provides the foundation for module dependency management
# Must be loaded before any other modules that use metadata

# Global associative array to track module metadata and loading state
typeset -gA MODULE_METADATA

# Initialize metadata system
_init_module_metadata() {
  # Prevent double initialization
  [[ -n "$_MODULE_METADATA_INITIALIZED" ]] && return 0

  # Initialize core metadata tracking
  MODULE_METADATA[system.initialized]="1"
  MODULE_METADATA[system.debug]="${DOTS_DEBUG:-0}"
  MODULE_METADATA[system.start_time]="$(date +%s.%3N)"

  # Mark system as initialized
  _MODULE_METADATA_INITIALIZED=1

  [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && echo "Module metadata system initialized"
}

# Declare module metadata
# Usage: declare_module "module_name" "depends:dep1,dep2" "provides:func1,func2" "optional:opt1"
declare_module() {
  local module_name="$1"
  shift

  # Initialize module metadata
  MODULE_METADATA[$module_name.loaded]="0"
  MODULE_METADATA[$module_name.load_time]=""
  MODULE_METADATA[$module_name.compile_time]=""

  # Parse metadata parameters
  for param in "$@"; do
    case "$param" in
      depends:*)
        MODULE_METADATA[$module_name.depends]="${param#depends:}"
        ;;
      provides:*)
        MODULE_METADATA[$module_name.provides]="${param#provides:}"
        ;;
      optional:*)
        MODULE_METADATA[$module_name.optional]="${param#optional:}"
        ;;
      description:*)
        MODULE_METADATA[$module_name.description]="${param#description:}"
        ;;
      category:*)
        MODULE_METADATA[$module_name.category]="${param#category:}"
        ;;
      external:*)
        MODULE_METADATA[$module_name.external]="${param#external:}"
        ;;
    esac
  done

  [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
    echo "Declared module: $module_name (deps: ${MODULE_METADATA[$module_name.depends]:-none})"
}

# Check if a module is loaded
is_module_loaded() {
  local module_name="$1"
  [[ "${MODULE_METADATA[$module_name.loaded]}" == "1" ]]
}

# Check module dependencies
check_module_deps() {
  local module_name="$1"
  local deps="${MODULE_METADATA[$module_name.depends]}"
  local missing_deps=()

  # No dependencies means it's safe to load
  [[ -z "$deps" ]] && return 0

  # Check each dependency
  for dep in ${(s:,:)deps}; do
    if ! is_module_loaded "$dep"; then
      missing_deps+=("$dep")
    fi
  done

  # If there are missing dependencies, report them
  if (( ${#missing_deps[@]} > 0 )); then
    echo "Error: Module '$module_name' requires these modules to be loaded first: ${missing_deps[*]}" >&2
    return 1
  fi

  return 0
}

# Check optional dependencies and warn if missing
check_optional_deps() {
  local module_name="$1"
  local optional="${MODULE_METADATA[$module_name.optional]}"
  local missing_optional=()

  [[ -z "$optional" ]] && return 0

  for opt in ${(s:,:)optional}; do
    if ! is_module_loaded "$opt"; then
      missing_optional+=("$opt")
    fi
  done

  # Warn about missing optional dependencies
  if (( ${#missing_optional[@]} > 0 )) && [[ "${MODULE_METADATA[system.debug]}" == "1" ]]; then
    echo "Warning: Module '$module_name' recommends these optional modules: ${missing_optional[*]}" >&2
  fi
}

# Check external dependencies
check_external_deps() {
  local module_name="$1"
  local external="${MODULE_METADATA[$module_name.external]}"
  local missing_external=()

  [[ -z "$external" ]] && return 0

  for cmd in ${(s:,:)external}; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_external+=("$cmd")
    fi
  done

  # Warn about missing external dependencies
  if (( ${#missing_external[@]} > 0 )) && [[ "${MODULE_METADATA[system.debug]}" == "1" ]]; then
    echo "Warning: Module '$module_name' depends on external commands: ${missing_external[*]}" >&2
  fi
}

# Mark a module as loaded
mark_module_loaded() {
  local module_name="$1"
  local load_time="${2:-$(date +%s.%3N)}"

  MODULE_METADATA[$module_name.loaded]="1"
  MODULE_METADATA[$module_name.load_time]="$load_time"

  [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
    echo "Module loaded: $module_name"
}

# Get loading order based on dependencies
get_load_order() {
  local -A visited
  local -A in_progress
  local load_order=()

  # Topological sort function
  _visit_module() {
    local module="$1"

    # Check for circular dependency
    if [[ -n "${in_progress[$module]}" ]]; then
      echo "Error: Circular dependency detected involving module '$module'" >&2
      return 1
    fi

    # Skip if already visited
    [[ -n "${visited[$module]}" ]] && return 0

    # Mark as in progress
    in_progress[$module]=1

    # Visit dependencies first
    local deps="${MODULE_METADATA[$module.depends]}"
    if [[ -n "$deps" ]]; then
      for dep in ${(s:,:)deps}; do
        _visit_module "$dep" || return 1
      done
    fi

    # Mark as visited and add to load order
    visited[$module]=1
    unset "in_progress[$module]"
    load_order+=("$module")
  }

  # Visit all declared modules
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.loaded ]] && [[ "${MODULE_METADATA[$key]}" == "0" ]]; then
      local module="${key%.loaded}"
      _visit_module "$module" || return 1
    fi
  done

  # Output the computed load order
  printf '%s\n' "${load_order[@]}"
}

# Display module information
show_module_info() {
  local module_name="$1"

  if [[ -z "${MODULE_METADATA[$module_name.loaded]}" ]]; then
    echo "Module '$module_name' is not declared"
    return 1
  fi

  echo "Module: $module_name"
  echo "  Status: $(is_module_loaded "$module_name" && echo "loaded" || echo "not loaded")"
  echo "  Category: ${MODULE_METADATA[$module_name.category]:-unknown}"
  echo "  Description: ${MODULE_METADATA[$module_name.description]:-none}"
  echo "  Dependencies: ${MODULE_METADATA[$module_name.depends]:-none}"
  echo "  Optional: ${MODULE_METADATA[$module_name.optional]:-none}"
  echo "  External: ${MODULE_METADATA[$module_name.external]:-none}"
  echo "  Provides: ${MODULE_METADATA[$module_name.provides]:-none}"

  if is_module_loaded "$module_name"; then
    echo "  Load time: ${MODULE_METADATA[$module_name.load_time]}"
    echo "  Compile time: ${MODULE_METADATA[$module_name.compile_time]}"
  fi
}

# List all modules by category
list_modules() {
  local category_filter="$1"
  local -A categories

  # Collect modules by category
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.loaded ]]; then
      local module="${key%.loaded}"
      local category="${MODULE_METADATA[$module.category]:-uncategorized}"

      # Apply category filter if specified
      if [[ -n "$category_filter" ]] && [[ "$category" != "$category_filter" ]]; then
        continue
      fi

      local module_status=$(is_module_loaded "$module" && echo "✓" || echo "○")
      categories[$category]+="  $module_status $module\n"
    fi
  done

  # Display modules by category
  for category in ${(ko)categories}; do
    echo "$category:"
    printf "${categories[$category]}"
    echo
  done
}

# Generate dependency graph in DOT format for visualization
generate_dependency_graph() {
  echo "digraph module_dependencies {"
  echo "  rankdir=TD;"
  echo "  node [shape=box, style=rounded];"
  echo

  # Add nodes with colors based on category
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.loaded ]]; then
      local module="${key%.loaded}"
      local category="${MODULE_METADATA[$module.category]:-uncategorized}"
      local color="lightgray"

      case "$category" in
        core) color="lightblue" ;;
        config) color="lightgreen" ;;
        tools) color="lightyellow" ;;
        ui) color="lightpink" ;;
        utils) color="lightcyan" ;;
        experimental) color="orange" ;;
      esac

      echo "  \"$module\" [fillcolor=\"$color\", style=\"filled,rounded\"];"
    fi
  done

  echo

  # Add dependency edges
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.depends ]]; then
      local module="${key%.depends}"
      local deps="${MODULE_METADATA[$key]}"

      if [[ -n "$deps" ]]; then
        for dep in ${(s:,:)deps}; do
          echo "  \"$dep\" -> \"$module\";"
        done
      fi
    fi
  done

  echo "}"
}

# Performance tracking
get_loading_stats() {
  local total_modules=0
  local loaded_modules=0
  local total_time=0

  echo "Module Loading Statistics:"
  echo "========================="

  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.loaded ]]; then
      local module="${key%.loaded}"
      ((total_modules++))

      if is_module_loaded "$module"; then
        ((loaded_modules++))
        local load_time="${MODULE_METADATA[$module.load_time]}"
        if [[ -n "$load_time" ]]; then
          # Calculate load duration (this is simplified - would need start time tracking)
          echo "  $module: loaded"
        fi
      else
        echo "  $module: not loaded"
      fi
    fi
  done

  echo
  echo "Summary: $loaded_modules/$total_modules modules loaded"

  if [[ -n "${MODULE_METADATA[system.start_time]}" ]]; then
    local end_time="$(date +%s.%3N)"
    local total_time=$(echo "$end_time - ${MODULE_METADATA[system.start_time]}" | bc 2>/dev/null || echo "unknown")
    echo "Total initialization time: ${total_time}s"
  fi
}

# Initialize the metadata system
_init_module_metadata

# Module metadata declaration (after functions are defined)
declare_module "metadata" \
  "category:core" \
  "description:Module metadata system and dependency management" \
  "provides:declare_module,is_module_loaded,check_module_deps,mark_module_loaded,get_load_order"
