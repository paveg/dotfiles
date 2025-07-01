#!/usr/bin/env bash
# ============================================================================
# Module Documentation Generator
#
# Automatically generates documentation from module metadata declarations.
# Creates both markdown documentation and dependency graphs.
#
# Usage:
#   ./scripts/generate-module-docs.sh [--output docs/modules.md] [--graph]
# ============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$PROJECT_ROOT/dot_config/zsh/modules"
OUTPUT_FILE="$PROJECT_ROOT/docs/MODULE_REFERENCE.md"
GENERATE_GRAPH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --graph)
            GENERATE_GRAPH=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create output directory
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Extract module metadata from a file
extract_metadata() {
    local file="$1"
    local module_name="$(basename "$file" .zsh)"
    
    # Extract declare_module call
    local metadata_line=$(grep -n "declare_module" "$file" | head -1 | cut -d: -f2-)
    
    if [[ -z "$metadata_line" ]]; then
        echo "# $module_name: No metadata found"
        return 1
    fi
    
    # Parse metadata parameters
    local depends=""
    local provides=""
    local category=""
    local description=""
    local external=""
    local optional=""
    
    # Extract parameters (simplified parsing)
    while IFS= read -r line; do
        if [[ "$line" =~ \"depends:([^\"]+)\" ]]; then
            depends="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"provides:([^\"]+)\" ]]; then
            provides="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"category:([^\"]+)\" ]]; then
            category="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"description:([^\"]+)\" ]]; then
            description="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"external:([^\"]+)\" ]]; then
            external="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"optional:([^\"]+)\" ]]; then
            optional="${BASH_REMATCH[1]}"
        fi
    done < <(sed -n '/declare_module/,/^[[:space:]]*$/p' "$file")
    
    # Output metadata in structured format
    cat << EOF
module_name="$module_name"
category="$category"
description="$description"
depends="$depends"
provides="$provides"
external="$external"
optional="$optional"
file_path="${file#$PROJECT_ROOT/}"
EOF
}

# Generate documentation
generate_docs() {
    echo "Generating module documentation..."
    
    # Create temporary file for metadata
    local temp_metadata=$(mktemp)
    
    # Extract metadata from all modules
    find "$MODULES_DIR" -name "*.zsh" -type f | while read -r module_file; do
        echo "# Processing: $module_file"
        extract_metadata "$module_file" >> "$temp_metadata"
        echo >> "$temp_metadata"
    done
    
    # Generate markdown documentation
    cat > "$OUTPUT_FILE" << 'HEADER'
# Zsh Module Reference

This document is automatically generated from module metadata declarations.

## Overview

The zsh configuration uses an enhanced module system with dependency resolution and categorized organization. Each module declares its dependencies, provides functions, and external tool requirements.

## Module Categories

- **core**: Essential modules that must load early (platform detection, core functions)
- **config**: Basic configuration modules  
- **tools**: Tool-specific integrations and plugin management
- **ui**: User interface enhancements (key bindings, prompts)
- **utils**: Utility functions and command aliases
- **experimental**: Optional experimental features
- **local**: Local machine-specific overrides

HEADER

    # Add dependency graph section
    if [[ "$GENERATE_GRAPH" == "true" ]]; then
        echo "" >> "$OUTPUT_FILE"
        echo "## Module Dependency Graph" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo '```mermaid' >> "$OUTPUT_FILE"
        echo 'graph TD' >> "$OUTPUT_FILE"
        
        # Generate mermaid graph
        while IFS= read -r line; do
            if [[ "$line" =~ ^module_name=\"([^\"]+)\" ]]; then
                local current_module="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^depends=\"([^\"]+)\" ]] && [[ -n "${BASH_REMATCH[1]}" ]]; then
                local deps="${BASH_REMATCH[1]}"
                IFS=',' read -ra DEP_ARRAY <<< "$deps"
                for dep in "${DEP_ARRAY[@]}"; do
                    echo "    $dep --> $current_module" >> "$OUTPUT_FILE"
                done
            fi
        done < "$temp_metadata"
        
        echo '```' >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    # Generate module reference by category
    echo "## Module Reference" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Group modules by category
    declare -A categories
    local current_module=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^module_name=\"([^\"]+)\" ]]; then
            current_module="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^category=\"([^\"]+)\" ]]; then
            local category="${BASH_REMATCH[1]}"
            if [[ -z "$category" ]]; then
                category="uncategorized"
            fi
            categories[$category]+="$current_module "
        fi
    done < "$temp_metadata"
    
    # Generate documentation for each category
    for category in core config tools ui utils experimental local uncategorized; do
        if [[ -n "${categories[$category]:-}" ]]; then
            echo "### ${category^} Modules" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            
            # Process each module in this category
            for module in ${categories[$category]}; do
                echo "#### $module" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
                
                # Extract full metadata for this module
                local module_section=$(awk "/module_name=\"$module\"/,/^$/" "$temp_metadata")
                
                local description=$(echo "$module_section" | grep '^description=' | cut -d= -f2- | tr -d '"')
                local depends=$(echo "$module_section" | grep '^depends=' | cut -d= -f2- | tr -d '"')
                local provides=$(echo "$module_section" | grep '^provides=' | cut -d= -f2- | tr -d '"')
                local external=$(echo "$module_section" | grep '^external=' | cut -d= -f2- | tr -d '"')
                local optional=$(echo "$module_section" | grep '^optional=' | cut -d= -f2- | tr -d '"')
                local file_path=$(echo "$module_section" | grep '^file_path=' | cut -d= -f2- | tr -d '"')
                
                echo "- **File**: \`$file_path\`" >> "$OUTPUT_FILE"
                echo "- **Description**: $description" >> "$OUTPUT_FILE"
                echo "- **Dependencies**: ${depends:-none}" >> "$OUTPUT_FILE"
                echo "- **Optional**: ${optional:-none}" >> "$OUTPUT_FILE"
                echo "- **Provides**: ${provides:-none}" >> "$OUTPUT_FILE"
                echo "- **External Tools**: ${external:-none}" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
            done
        fi
    done
    
    # Add usage section
    cat >> "$OUTPUT_FILE" << 'USAGE'
## Usage

### Module System Commands

The module system provides several commands for management and debugging:

```zsh
# List all modules by category
modules

# Show detailed information about a module
module-info <module_name>

# Reload a module and its dependents
module-reload <module_name>

# Validate module system integrity
module-validate

# Show debug information
module-debug

# Show loading statistics
module-stats

# Generate dependency graph (DOT format)
module-graph

# Show help for module commands
module-help
```

### Environment Variables

Control module loading behavior with these environment variables:

```zsh
# Enable debug output
export DOTS_DEBUG=1

# Skip specific modules
export DOTS_SKIP_MODULES="logging,strings"

# Load only specific modules (for testing)
export DOTS_ONLY_MODULES="platform,core,config"
```

### Development

When developing new modules:

1. Create the module file in the appropriate category directory
2. Add metadata declaration at the top:
   ```zsh
   declare_module "module_name" \
     "depends:dependency1,dependency2" \
     "category:category_name" \
     "description:Brief description" \
     "provides:function1,function2" \
     "external:command1,command2"
   ```
3. Test the module: `module-validate`
4. Update documentation: `./scripts/generate-module-docs.sh --graph`

### Testing

Load subsets of modules for testing:

```zsh
# Load only core modules
load_core_only

# Load minimal set
load_minimal

# Test specific configuration
DOTS_ONLY_MODULES="platform,core,alias" zsh -l
```

## Migration

To migrate from the old flat structure to the new categorized system:

```bash
# Run migration script
./scripts/migrate-modules.sh --backup

# Test the migration
DOTS_DEBUG=1 zsh -l

# Validate everything works
module-validate
```

## Performance

The module system is optimized for performance:

- **Dependency resolution**: Modules load in optimal order
- **Lazy loading**: Optional features load on demand
- **Compilation**: All modules compile to .zwc for faster loading
- **Caching**: Completion system uses intelligent caching
- **Conditional loading**: Tools initialize based on shell context

Monitor performance with:
```zsh
# Show startup time with details
DOTS_DEBUG=1 zsh -l

# Profile startup performance
zprofiler

# Measure multiple startup times
zshtime
```
USAGE
    
    # Cleanup
    rm -f "$temp_metadata"
    
    echo "Documentation generated: $OUTPUT_FILE"
}

# Generate dependency graph in DOT format
generate_dot_graph() {
    local output_file="$PROJECT_ROOT/docs/module_dependencies.dot"
    
    echo "Generating dependency graph..."
    
    cat > "$output_file" << 'HEADER'
digraph module_dependencies {
    rankdir=TD;
    node [shape=box, style="rounded,filled"];
    
    // Category-based coloring
    node [fillcolor=lightblue] platform terminal core path metadata loader;
    node [fillcolor=lightgreen] config;
    node [fillcolor=lightyellow] plugin;
    node [fillcolor=lightpink] keybind;
    node [fillcolor=lightcyan] alias func local;
    node [fillcolor=orange] logging strings;
    
HEADER
    
    # Extract dependencies and add edges
    find "$MODULES_DIR" -name "*.zsh" -type f | while read -r module_file; do
        local module_name="$(basename "$module_file" .zsh)"
        
        # Extract dependencies
        local deps=$(grep -o 'depends:[^"]*' "$module_file" | cut -d: -f2 | head -1)
        
        if [[ -n "$deps" ]]; then
            IFS=',' read -ra DEP_ARRAY <<< "$deps"
            for dep in "${DEP_ARRAY[@]}"; do
                echo "    $dep -> $module_name;" >> "$output_file"
            done
        fi
    done
    
    echo "}" >> "$output_file"
    
    echo "DOT graph generated: $output_file"
    
    # Try to generate PNG if graphviz is available
    if command -v dot >/dev/null 2>&1; then
        local png_file="$PROJECT_ROOT/docs/module_dependencies.png"
        dot -Tpng "$output_file" -o "$png_file"
        echo "PNG graph generated: $png_file"
    fi
}

# Main execution
main() {
    echo "Module Documentation Generator"
    echo "=============================="
    
    if [[ ! -d "$MODULES_DIR" ]]; then
        echo "Error: Modules directory not found: $MODULES_DIR"
        exit 1
    fi
    
    generate_docs
    
    if [[ "$GENERATE_GRAPH" == "true" ]]; then
        generate_dot_graph
    fi
    
    echo "Documentation generation completed!"
}

main "$@"