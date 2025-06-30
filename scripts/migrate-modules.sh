#!/usr/bin/env bash
# ============================================================================
# Module System Migration Script
#
# This script helps migrate from the old flat module structure to the new
# categorized module dependency system.
#
# Usage:
#   ./scripts/migrate-modules.sh [--dry-run] [--backup] [--force]
#
# Options:
#   --dry-run    Show what would be done without making changes
#   --backup     Create backup before migration
#   --force      Skip confirmation prompts
# ============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZSH_DIR="$PROJECT_ROOT/dot_config/zsh"
MODULES_DIR="$ZSH_DIR/modules"

# Migration options
DRY_RUN=false
CREATE_BACKUP=false
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --backup)
                CREATE_BACKUP=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Module System Migration Script

This script migrates from the old flat module structure to the new
categorized module dependency system.

Usage: $0 [OPTIONS]

Options:
    --dry-run    Show what would be done without making changes
    --backup     Create backup before migration  
    --force      Skip confirmation prompts
    -h, --help   Show this help message

Migration Steps:
1. Backup existing configuration (if --backup specified)
2. Check current module structure
3. Create new categorized directory structure
4. Move modules to appropriate categories
5. Update .zshrc to use new init system
6. Validate the migration

EOF
}

# Check if we're in the right directory
check_environment() {
    if [[ ! -d "$ZSH_DIR" ]]; then
        log_error "Zsh configuration directory not found: $ZSH_DIR"
        log_error "Please run this script from the dotfiles repository root"
        exit 1
    fi
    
    if [[ ! -d "$MODULES_DIR" ]]; then
        log_error "Modules directory not found: $MODULES_DIR"
        exit 1
    fi
    
    log_info "Environment check passed"
}

# Create backup of current configuration
create_backup() {
    [[ "$CREATE_BACKUP" == "false" ]] && return 0
    
    local backup_dir="$ZSH_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    
    log_info "Creating backup: $backup_dir"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cp -r "$ZSH_DIR" "$backup_dir"
        log_success "Backup created: $backup_dir"
    else
        log_info "[DRY-RUN] Would create backup: $backup_dir"
    fi
}

# Check current module structure
check_current_structure() {
    log_info "Checking current module structure..."
    
    # Check if we have the new structure already
    if [[ -d "$MODULES_DIR/core" ]]; then
        log_warning "New module structure already exists"
        
        if [[ "$FORCE" == "false" ]]; then
            read -p "Continue with migration? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Migration cancelled"
                exit 0
            fi
        fi
    fi
    
    # List current modules
    log_info "Current modules:"
    for module in "$MODULES_DIR"/*.zsh; do
        if [[ -f "$module" ]]; then
            echo "  - $(basename "$module")"
        fi
    done
}

# Create new directory structure
create_new_structure() {
    log_info "Creating new module directory structure..."
    
    local categories=(
        "core"
        "config"
        "tools"
        "ui"
        "utils"
        "experimental"
        "local"
    )
    
    for category in "${categories[@]}"; do
        local dir="$MODULES_DIR/$category"
        if [[ "$DRY_RUN" == "false" ]]; then
            mkdir -p "$dir"
            log_success "Created directory: $category/"
        else
            log_info "[DRY-RUN] Would create directory: $category/"
        fi
    done
}

# Move modules to appropriate categories
migrate_modules() {
    log_info "Migrating modules to categorized structure..."
    
    # Define module categorization
    declare -A module_categories=(
        ["platform.zsh"]="core"
        ["terminal.zsh"]="core"
        ["core.zsh"]="core"
        ["path.zsh"]="core"
        ["metadata.zsh"]="core"
        ["loader.zsh"]="core"
        ["config.zsh"]="config"
        ["plugin.zsh"]="tools"
        ["keybind.zsh"]="ui"
        ["alias.zsh"]="utils"
        ["func.zsh"]="utils"
        ["local.zsh"]="local"
        ["logging.zsh"]="experimental"
        ["strings.zsh"]="experimental"
    )
    
    # Move modules
    for module in "$MODULES_DIR"/*.zsh; do
        if [[ ! -f "$module" ]]; then
            continue
        fi
        
        local module_name="$(basename "$module")"
        local category="${module_categories[$module_name]:-uncategorized}"
        
        if [[ "$category" == "uncategorized" ]]; then
            log_warning "Unknown module category for: $module_name"
            continue
        fi
        
        local target_dir="$MODULES_DIR/$category"
        local target_file="$target_dir/$module_name"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            if [[ -f "$target_file" ]]; then
                log_warning "Target file already exists: $target_file"
                continue
            fi
            
            mv "$module" "$target_file"
            log_success "Moved $module_name to $category/"
        else
            log_info "[DRY-RUN] Would move $module_name to $category/"
        fi
    done
}

# Update .zshrc to use new system
update_zshrc() {
    log_info "Updating .zshrc to use new module system..."
    
    local zshrc_file="$ZSH_DIR/dot_zshrc.tmpl"
    local new_zshrc_file="$ZSH_DIR/dot_zshrc_new.tmpl"
    
    if [[ ! -f "$new_zshrc_file" ]]; then
        log_error "New .zshrc template not found: $new_zshrc_file"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Backup original
        if [[ -f "$zshrc_file" ]]; then
            cp "$zshrc_file" "$zshrc_file.backup"
            log_success "Backed up original .zshrc"
        fi
        
        # Replace with new version
        mv "$new_zshrc_file" "$zshrc_file"
        log_success "Updated .zshrc to use new module system"
    else
        log_info "[DRY-RUN] Would update .zshrc with new module system"
    fi
}

# Validate migration
validate_migration() {
    log_info "Validating migration..."
    
    # Check that all expected directories exist
    local categories=("core" "config" "tools" "ui" "utils" "experimental" "local")
    local errors=0
    
    for category in "${categories[@]}"; do
        if [[ ! -d "$MODULES_DIR/$category" ]]; then
            log_error "Missing category directory: $category"
            ((errors++))
        fi
    done
    
    # Check that core modules exist
    local core_modules=("platform.zsh" "core.zsh" "metadata.zsh" "loader.zsh")
    for module in "${core_modules[@]}"; do
        if [[ ! -f "$MODULES_DIR/core/$module" ]]; then
            log_error "Missing core module: $module"
            ((errors++))
        fi
    done
    
    # Check that init.zsh exists
    if [[ ! -f "$ZSH_DIR/init.zsh" ]]; then
        log_error "Missing init.zsh file"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Migration validation passed"
        return 0
    else
        log_error "Migration validation failed with $errors errors"
        return 1
    fi
}

# Test the new system
test_new_system() {
    log_info "Testing new module system..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test new module system"
        return 0
    fi
    
    # Create a temporary shell script to test loading
    local test_script="$MODULES_DIR/test_loading.zsh"
    
    cat > "$test_script" << 'EOF'
#!/usr/bin/env zsh
# Test script for new module system

# Set up environment
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export DOTS_DEBUG=1

# Test loading
source "$ZDOTDIR/init.zsh"

# Report results
echo "Module system test completed"
if (( $+functions[list_modules] )); then
    echo "✓ Module management functions available"
    list_modules
else
    echo "✗ Module management functions not available"
    exit 1
fi
EOF
    
    chmod +x "$test_script"
    
    # Run the test
    if zsh "$test_script"; then
        log_success "Module system test passed"
        rm -f "$test_script"
        return 0
    else
        log_error "Module system test failed"
        log_info "Test script saved for debugging: $test_script"
        return 1
    fi
}

# Main migration function
run_migration() {
    log_info "Starting module system migration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no changes will be made"
    fi
    
    # Confirmation prompt
    if [[ "$FORCE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        echo
        log_warning "This will modify your zsh configuration structure."
        if [[ "$CREATE_BACKUP" == "true" ]]; then
            echo "A backup will be created before making changes."
        else
            echo "No backup will be created. Use --backup to create one."
        fi
        echo
        read -p "Continue with migration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Migration cancelled"
            exit 0
        fi
    fi
    
    # Run migration steps
    check_environment
    create_backup
    check_current_structure
    create_new_structure
    migrate_modules
    update_zshrc
    
    if [[ "$DRY_RUN" == "false" ]]; then
        validate_migration
        test_new_system
        
        log_success "Migration completed successfully!"
        echo
        log_info "Next steps:"
        echo "1. Test your zsh configuration: zsh -l"
        echo "2. Check module loading: DOTS_DEBUG=1 zsh -l"
        echo "3. Use 'modules' command to see module status"
        echo "4. Use 'module-help' to see available commands"
    else
        log_info "Dry run completed. Use without --dry-run to apply changes."
    fi
}

# Main execution
main() {
    parse_args "$@"
    run_migration
}

# Run main function with all arguments
main "$@"