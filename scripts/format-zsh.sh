#!/usr/bin/env bash
# ============================================================================
# Zsh File Formatter
#
# This script formats zsh configuration files for consistency and readability.
#
# Features:
# - Removes trailing whitespace
# - Ensures final newline
# - Standardizes shebang lines
# - Validates syntax
# - Consistent indentation check
# - Removes unnecessary blank lines
# ============================================================================

set -euo pipefail

# Cleanup function for backup files
cleanup_backups() {
    # Only run cleanup if we're in the right directory
    if [[ -d "dot_config" || -d ".github" ]]; then
        find . -name "*.backup.*" -type f -delete 2>/dev/null || true
    fi
}

# Note: Cleanup runs explicitly at the end of main() function

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SHEBANG="#!/usr/bin/env zsh"
MAX_CONSECUTIVE_BLANK_LINES=2

# Print colored output
print_status() {
    local color=$1
    local message=$2
    printf "${color}%s${NC}\n" "$message"
}

print_info() { print_status "$BLUE" "ℹ $1"; }
print_success() { print_status "$GREEN" "✓ $1"; }
print_warning() { print_status "$YELLOW" "⚠ $1"; }
print_error() { print_status "$RED" "✗ $1"; }

# Check if file is a zsh file (excluding history files)
is_zsh_file() {
    local file=$1
    local basename_file
    basename_file=$(basename "$file")

    # Exclude history files
    if [[ "$basename_file" =~ ^\.zsh_history ]] || [[ "$file" =~ _history$ ]]; then
        return 1
    fi

    [[ "$file" =~ \.(zsh|zshrc|zshenv|zprofile)$ ]] || [[ "$basename_file" =~ ^\.zsh ]]
}

# Fix shebang line
fix_shebang() {
    local file=$1
    local first_line
    first_line=$(head -n1 "$file" 2>/dev/null || echo "")

    # Skip non-module files (main config files don't need shebangs)
    if [[ ! "$file" =~ modules/ ]]; then
        return 0
    fi

    if [[ "$first_line" != "$SHEBANG" ]]; then
        if [[ "$first_line" =~ ^#! ]]; then
            # Replace existing shebang
            sed -i '' "1s|.*|$SHEBANG|" "$file"
            print_warning "Fixed shebang in $file"
        elif [[ -n "$first_line" ]]; then
            # Add shebang at the beginning
            sed -i '' "1i\\
$SHEBANG
" "$file"
            print_warning "Added shebang to $file"
        fi
    fi
}

# Remove trailing whitespace
remove_trailing_whitespace() {
    local file=$1
    local count
    count=$(grep -c '[[:space:]]$' "$file" 2>/dev/null || echo "0")
    count=$(echo "$count" | tr -d '\n')

    if [[ "$count" -gt 0 ]]; then
        sed -i '' 's/[[:space:]]*$//' "$file"
        print_warning "Removed trailing whitespace from $file ($count lines)"
    fi
}

# Ensure final newline
ensure_final_newline() {
    local file=$1
    if [[ -n "$(tail -c1 "$file" 2>/dev/null)" ]]; then
        echo >> "$file"
        print_warning "Added final newline to $file"
    fi
}

# Remove excessive blank lines
remove_excessive_blank_lines() {
    local file=$1
    local temp_file
    temp_file=$(mktemp)

    awk "
    BEGIN { blank_count = 0 }
    /^[[:space:]]*$/ {
        blank_count++
        if (blank_count <= $MAX_CONSECUTIVE_BLANK_LINES) print
        next
    }
    {
        blank_count = 0
        print
    }
    " "$file" > "$temp_file"

    if ! cmp -s "$file" "$temp_file"; then
        mv "$temp_file" "$file"
        print_warning "Reduced excessive blank lines in $file"
    else
        rm "$temp_file"
    fi
}

# Check indentation consistency
check_indentation() {
    local file=$1
    local has_tabs has_spaces

    has_tabs=$(grep -q $'\t' "$file" && echo "yes" || echo "no")
    has_spaces=$(grep -q '^  ' "$file" && echo "yes" || echo "no")

    if [[ "$has_tabs" == "yes" && "$has_spaces" == "yes" ]]; then
        print_warning "Mixed tabs and spaces in $file"
        return 1
    fi
    return 0
}

# Validate syntax
validate_syntax() {
    local file=$1
    if ! zsh -n "$file" 2>/dev/null; then
        print_error "Syntax error in $file"
        return 1
    fi
    return 0
}

# Format a single file
format_file() {
    local file=$1

    if [[ ! -f "$file" ]]; then
        print_error "File not found: $file"
        return 1
    fi

    if [[ ! -w "$file" ]]; then
        print_error "File not writable: $file"
        return 1
    fi

    print_info "Formatting $file..."

    # Create backup
    local backup_file="${file}.backup.$(date +%s)"
    cp "$file" "$backup_file"

    # Apply formatting
    fix_shebang "$file"
    remove_trailing_whitespace "$file"
    remove_excessive_blank_lines "$file"
    ensure_final_newline "$file"

    # Validate result
    if validate_syntax "$file"; then
        rm -f "$backup_file"
        check_indentation "$file" || true  # Don't fail on indentation warnings
        print_success "Formatted $file"
        return 0
    else
        # Restore backup on syntax error
        mv "$backup_file" "$file"
        print_error "Syntax error after formatting $file - restored backup"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [FILES...]

Format zsh configuration files for consistency and readability.

OPTIONS:
    -h, --help              Show this help message
    -d, --directory DIR     Format all zsh files in directory
    -r, --recursive         Recursively format files in subdirectories
    -c, --check             Check files without modifying (dry run)
    -v, --verbose           Verbose output

EXAMPLES:
    $0 .zshrc                           # Format single file
    $0 modules/*.zsh                    # Format all zsh files in modules/
    $0 -d . -r                          # Format all zsh files recursively
    $0 -c .zshrc                        # Check file without modifying

EOF
}

# Main function
main() {
    local files=()
    local directory=""
    local recursive=false
    local check_only=false
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--directory)
                directory="$2"
                shift 2
                ;;
            -r|--recursive)
                recursive=true
                shift
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done

    # Collect files to process
    local all_files=()

    if [[ -n "$directory" ]]; then
        if [[ "$recursive" == true ]]; then
            while IFS= read -r -d '' file; do
                if is_zsh_file "$file"; then
                    all_files+=("$file")
                fi
            done < <(find "$directory" -type f \( -name "*.zsh" -o -name ".zsh*" \) -print0)
        else
            for file in "$directory"/*.zsh "$directory"/.zsh*; do
                if [[ -f "$file" ]] && is_zsh_file "$file"; then
                    all_files+=("$file")
                fi
            done
        fi
    fi

    # Add explicitly specified files
    if [[ ${#files[@]} -gt 0 ]]; then
        for file in "${files[@]}"; do
            if [[ -f "$file" ]]; then
                all_files+=("$file")
            else
                print_warning "File not found: $file"
            fi
        done
    fi

    # Default to current directory if no files specified
    if [[ ${#all_files[@]} -eq 0 ]]; then
        for file in .zshrc .zshenv .zprofile modules/*.zsh; do
            if [[ -f "$file" ]] && is_zsh_file "$file"; then
                all_files+=("$file")
            fi
        done
    fi

    if [[ ${#all_files[@]} -eq 0 ]]; then
        print_error "No zsh files found to format"
        exit 1
    fi

    print_info "Found ${#all_files[@]} zsh files to process"

    # Process files
    local success_count=0
    local error_count=0

    for file in "${all_files[@]}"; do
        if [[ "$check_only" == true ]]; then
            # Check mode - validate syntax only
            if validate_syntax "$file"; then
                print_success "✓ $file"
                success_count=$((success_count + 1))
            else
                print_error "✗ $file"
                error_count=$((error_count + 1))
            fi
        else
            # Format mode
            if format_file "$file"; then
                success_count=$((success_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        fi
    done

    # Summary
    echo
    print_info "Summary:"
    print_success "Successfully processed: $success_count files"
    if [[ $error_count -gt 0 ]]; then
        print_error "Failed: $error_count files"
        exit 1
    fi

    # Clean up any remaining backup files (safety net)
    cleanup_backups
}

# Run main function
main "$@"
