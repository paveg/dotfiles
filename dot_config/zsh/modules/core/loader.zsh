#!/usr/bin/env zsh
# Enhanced Module Loader with Dependency Resolution
# This replaces the basic loading logic with intelligent dependency management

# Source the metadata system first
source "${${(%):-%x}:A:h}/metadata.zsh"

# Enhanced module loading function
load_module() {
  local module_file="$1"
  local force_reload="${2:-false}"

  # Extract module name from path
  local module_name="${module_file:t:r}"

  # Check if module is already loaded (unless force reload)
  if [[ "$force_reload" != "true" ]] && is_module_loaded "$module_name"; then
    [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
      echo "Module '$module_name' already loaded, skipping"
    return 0
  fi

  # Check if file exists
  if [[ ! -f "$module_file" ]]; then
    echo "Error: Module file not found: $module_file" >&2
    return 1
  fi

  # Record start time for performance tracking
  local start_time="$(date +%s.%3N)"

  # Source the module to get its metadata declaration
  # This is safer: extract just the declare_module line and eval it
  local declare_line
  declare_line=$(grep -m1 '^declare_module' "$module_file" 2>/dev/null || true)
  if [[ -n "$declare_line" ]]; then
    eval "$declare_line" 2>/dev/null || true
  fi

  # Check if module has been declared (has metadata)
  if [[ -z "${MODULE_METADATA[$module_name.loaded]}" ]]; then
    # Auto-declare module with basic metadata if not declared
    declare_module "$module_name" "category:legacy" "description:Auto-declared legacy module"
    [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
      echo "Auto-declared legacy module: $module_name"
  fi

  # Check dependencies before loading
  if ! check_module_deps "$module_name"; then
    echo "Error: Cannot load module '$module_name' due to missing dependencies" >&2
    return 1
  fi

  # Check optional dependencies (warn only)
  check_optional_deps "$module_name"

  # Check external dependencies (warn only)
  check_external_deps "$module_name"

  # Source the actual module
  local source_start="$(date +%s.%3N)"
  if source "$module_file"; then
    local source_end="$(date +%s.%3N)"
    local source_time=$(echo "$source_end - $source_start" | bc 2>/dev/null || echo "0")

    # Compile module for performance (using existing zcompare function if available)
    local compile_start="$(date +%s.%3N)"
    if (( $+functions[zcompare] )); then
      zcompare "$module_file"
    elif command -v zcompile >/dev/null 2>&1; then
      # Fallback compilation
      [[ "$module_file.zwc" -ot "$module_file" ]] && zcompile "$module_file" 2>/dev/null
    fi
    local compile_end="$(date +%s.%3N)"
    local compile_time=$(echo "$compile_end - $compile_start" | bc 2>/dev/null || echo "0")

    # Mark module as loaded with timing information
    mark_module_loaded "$module_name" "$source_end"
    MODULE_METADATA[$module_name.source_time]="$source_time"
    MODULE_METADATA[$module_name.compile_time]="$compile_time"

    local total_time=$(echo "$source_end - $start_time" | bc 2>/dev/null || echo "0")
    [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
      echo "Loaded module '$module_name' in ${total_time}s (source: ${source_time}s, compile: ${compile_time}s)"

    return 0
  else
    echo "Error: Failed to source module: $module_file" >&2
    return 1
  fi
}

# Load modules in dependency order
load_modules_ordered() {
  local module_dir="${1:-$XDG_CONFIG_HOME/zsh/modules}"
  local pattern="${2:-*.zsh}"

  [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
    echo "Loading modules from: $module_dir"

  # Find all module files
  local module_files=()
  for file in "$module_dir"/$~pattern(N); do
    # Skip the metadata and loader modules themselves
    local basename="${file:t}"
    if [[ "$basename" != "metadata.zsh" ]] && [[ "$basename" != "loader.zsh" ]]; then
      module_files+=("$file")
    fi
  done

  # If no specific modules declared, use legacy loading order
  local declared_modules=()
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.loaded ]]; then
      declared_modules+=("${key%.loaded}")
    fi
  done

  if (( ${#declared_modules[@]} == 0 )); then
    # Legacy mode: load in the traditional order
    [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
      echo "No module metadata found, using legacy loading order"

    local legacy_order=(
      platform terminal core config alias func keybind plugin local
    )

    for module_name in "${legacy_order[@]}"; do
      for file in "${module_files[@]}"; do
        if [[ "${file:t:r}" == "$module_name" ]]; then
          load_module "$file"
          break
        fi
      done
    done

    # Load any remaining modules not in the legacy order
    for file in "${module_files[@]}"; do
      local module_name="${file:t:r}"
      if ! is_module_loaded "$module_name"; then
        load_module "$file"
      fi
    done
  else
    # Modern mode: use dependency resolution
    [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
      echo "Using dependency-based loading order"

    local load_order
    if ! load_order=($(get_load_order)); then
      echo "Error: Cannot resolve module dependencies" >&2
      return 1
    fi

    # Load modules in computed order
    for module_name in "${load_order[@]}"; do
      # Find the file for this module
      local module_file=""
      for file in "${module_files[@]}"; do
        if [[ "${file:t:r}" == "$module_name" ]]; then
          module_file="$file"
          break
        fi
      done

      if [[ -n "$module_file" ]]; then
        load_module "$module_file"
      else
        echo "Warning: Module file not found for declared module: $module_name" >&2
      fi
    done
  fi

  # Report loading statistics
  if [[ "${MODULE_METADATA[system.debug]}" == "1" ]]; then
    get_loading_stats
  fi
}

# Load modules from specific categories
load_modules_by_category() {
  local category="$1"
  local module_dir="${2:-$XDG_CONFIG_HOME/zsh/modules}"
  local category_dir="$module_dir/$category"

  [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
    echo "Loading modules from category: $category"

  # Check if category directory exists
  if [[ ! -d "$category_dir" ]]; then
    [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
      echo "Category directory not found: $category_dir"
    return 0
  fi

  # Load all .zsh files from the category directory
  for module_file in "$category_dir"/*.zsh(N); do
    local module_name="${module_file:t:r}"

    # Skip if module should be skipped
    if should_skip_module "$module_name"; then
      continue
    fi

    # Skip if already loaded
    if is_module_loaded "$module_name"; then
      [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
        echo "Module '$module_name' already loaded, skipping"
      continue
    fi

    [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
      echo "Loading module from $category: $module_name"

    load_module "$module_file"
  done
}

# Reload a module and its dependents
reload_module() {
  local module_name="$1"
  local module_dir="${2:-$XDG_CONFIG_HOME/zsh/modules}"

  # Find dependents of this module
  local dependents=()
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.depends ]]; then
      local dependent_module="${key%.depends}"
      local deps="${MODULE_METADATA[$key]}"

      if [[ "$deps" == *"$module_name"* ]]; then
        dependents+=("$dependent_module")
      fi
    fi
  done

  # Unload dependents first (mark as not loaded)
  for dependent in "${dependents[@]}"; do
    if is_module_loaded "$dependent"; then
      MODULE_METADATA[$dependent.loaded]="0"
      [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
        echo "Unloaded dependent module: $dependent"
    fi
  done

  # Unload the target module
  MODULE_METADATA[$module_name.loaded]="0"
  [[ "${MODULE_METADATA[system.debug]}" == "1" ]] && \
    echo "Unloaded module: $module_name"

  # Reload the module
  local module_file="$module_dir/$module_name.zsh"
  if [[ -f "$module_file" ]]; then
    load_module "$module_file" true
  else
    echo "Error: Module file not found: $module_file" >&2
    return 1
  fi

  # Reload dependents
  for dependent in "${dependents[@]}"; do
    local dependent_file="$module_dir/$dependent.zsh"
    if [[ -f "$dependent_file" ]]; then
      load_module "$dependent_file" true
    fi
  done
}

# Validate module system integrity
validate_modules() {
  local errors=0

  echo "Validating module system..."

  # Check for circular dependencies
  if ! get_load_order >/dev/null 2>&1; then
    echo "✗ Circular dependency detected in module system"
    ((errors++))
  else
    echo "✓ No circular dependencies found"
  fi

  # Check that all dependencies are satisfied
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.depends ]]; then
      local module="${key%.depends}"
      local deps="${MODULE_METADATA[$key]}"

      if [[ -n "$deps" ]]; then
        for dep in ${(s:,:)deps}; do
          if [[ -z "${MODULE_METADATA[$dep.loaded]}" ]]; then
            echo "✗ Module '$module' depends on undeclared module '$dep'"
            ((errors++))
          fi
        done
      fi
    fi
  done

  # Check for missing module files (check both old flat structure and new organized structure)
  local module_dir="${XDG_CONFIG_HOME}/zsh/modules"
  for key in ${(k)MODULE_METADATA}; do
    if [[ "$key" == *.loaded ]]; then
      local module="${key%.loaded}"
      local module_file=""

      # Check organized structure first
      for category in core config utils ui tools experimental local; do
        if [[ -f "$module_dir/$category/$module.zsh" ]]; then
          module_file="$module_dir/$category/$module.zsh"
          break
        fi
      done

      # Fall back to flat structure
      if [[ -z "$module_file" ]] && [[ -f "$module_dir/$module.zsh" ]]; then
        module_file="$module_dir/$module.zsh"
      fi

      if [[ -z "$module_file" ]]; then
        echo "✗ Module file missing for declared module '$module' (checked organized and flat structures)"
        ((errors++))
      fi
    fi
  done

  if (( errors == 0 )); then
    echo "✓ Module system validation passed"
    return 0
  else
    echo "✗ Module system validation failed with $errors errors"
    return 1
  fi
}

# Debug helper to show current module state
debug_modules() {
  echo "Module System Debug Information"
  echo "=============================="
  echo

  echo "System Status:"
  echo "  Metadata initialized: ${_MODULE_METADATA_INITIALIZED:-no}"
  echo "  Debug mode: ${MODULE_METADATA[system.debug]:-0}"
  echo "  Start time: ${MODULE_METADATA[system.start_time]:-unknown}"
  echo

  echo "Modules by Status:"
  list_modules

  echo "Dependency Graph (DOT format):"
  generate_dependency_graph
}

# Module metadata declaration (after functions are defined)
declare_module "loader" \
  "depends:metadata" \
  "category:core" \
  "description:Enhanced module loader with dependency resolution" \
  "provides:load_module,load_modules_ordered,load_modules_by_category,reload_module,validate_modules"
