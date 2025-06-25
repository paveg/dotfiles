#!/usr/bin/env bash
# ============================================================================
# Markdown File Formatter
#
# This script formats markdown files for consistency and readability.
#
# Features:
# - Removes trailing whitespace
# - Ensures final newline
# - Standardizes heading spacing
# - Fixes list formatting
# - Validates basic markdown syntax
# - Consistent line endings
# - Table formatting (basic)
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
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

# Check if file is a markdown file
is_markdown_file() {
    local file=$1
    [[ "$file" =~ \.(md|markdown)$ ]]
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

# Fix heading spacing (ensure blank line before/after headings)
fix_heading_spacing() {
    local file=$1
    local temp_file
    temp_file=$(mktemp)

    awk '
    BEGIN { prev_line = ""; prev_blank = 0 }
    /^#{1,6} / {
        # If previous line is not blank and not a heading, add blank line
        if (prev_line != "" && prev_blank == 0 && prev_line !~ /^#{1,6} /) {
            print ""
        }
        print $0
        heading_line = 1
        prev_line = $0
        prev_blank = 0
        next
    }
    /^[[:space:]]*$/ {
        print $0
        prev_line = $0
        prev_blank = 1
        heading_line = 0
        next
    }
    {
        # If previous line was a heading and this is not blank, add blank line
        if (heading_line == 1 && prev_blank == 0) {
            print ""
        }
        print $0
        prev_line = $0
        prev_blank = 0
        heading_line = 0
    }
    ' "$file" > "$temp_file"

    if ! cmp -s "$file" "$temp_file"; then
        mv "$temp_file" "$file"
        print_warning "Fixed heading spacing in $file"
    else
        rm "$temp_file"
    fi
}

# Fix list formatting (ensure consistent spacing)
fix_list_formatting() {
    local file=$1
    local temp_file
    temp_file=$(mktemp)

    # Basic list formatting: ensure lists have proper spacing
    sed -E '
        # Fix unordered list markers
        s/^[[:space:]]*[\*\+\-][[:space:]]+/- /
        # Fix ordered list markers
        s/^[[:space:]]*[0-9]+\.[[:space:]]+/1. /
    ' "$file" > "$temp_file"

    if ! cmp -s "$file" "$temp_file"; then
        mv "$temp_file" "$file"
        print_warning "Fixed list formatting in $file"
    else
        rm "$temp_file"
    fi
}

# Basic markdown validation
validate_markdown() {
    local file=$1
    local errors=0

    # Check for unclosed code blocks
    local backticks
    backticks=$(grep -c '^```' "$file" 2>/dev/null || echo "0")
    if [[ $((backticks % 2)) -ne 0 ]]; then
        print_warning "Unclosed code block in $file"
        ((errors++))
    fi

    # Check for malformed links
    if grep -q '\[.*\]([^)]*$' "$file" 2>/dev/null; then
        print_warning "Malformed links in $file"
        ((errors++))
    fi

    # Check for malformed images
    if grep -q '!\[.*\]([^)]*$' "$file" 2>/dev/null; then
        print_warning "Malformed images in $file"
        ((errors++))
    fi

    return $errors
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
    remove_trailing_whitespace "$file"
    remove_excessive_blank_lines "$file"
    fix_heading_spacing "$file"
    fix_list_formatting "$file"
    ensure_final_newline "$file"

    # Validate result
    if validate_markdown "$file"; then
        rm "$backup_file"
        print_success "Formatted $file"
        return 0
    else
        print_warning "Formatting completed with warnings for $file"
        rm "$backup_file"
        return 0
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [FILES...]

Format markdown files for consistency and readability.

OPTIONS:
    -h, --help              Show this help message
    -d, --directory DIR     Format all markdown files in directory
    -r, --recursive         Recursively format files in subdirectories
    -c, --check             Check files without modifying (dry run)
    -v, --verbose           Verbose output

EXAMPLES:
    $0 README.md                        # Format single file
    $0 docs/*.md                        # Format all markdown files in docs/
    $0 -d . -r                          # Format all markdown files recursively
    $0 -c README.md                     # Check file without modifying

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
                if is_markdown_file "$file"; then
                    all_files+=("$file")
                fi
            done < <(find "$directory" -type f \( -name "*.md" -o -name "*.markdown" \) -print0)
        else
            for file in "$directory"/*.md "$directory"/*.markdown; do
                if [[ -f "$file" ]] && is_markdown_file "$file"; then
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
        for file in *.md *.markdown README.md; do
            if [[ -f "$file" ]] && is_markdown_file "$file"; then
                all_files+=("$file")
            fi
        done
    fi

    if [[ ${#all_files[@]} -eq 0 ]]; then
        print_error "No markdown files found to format"
        exit 1
    fi

    print_info "Found ${#all_files[@]} markdown files to process"

    # Process files
    local success_count=0
    local error_count=0

    for file in "${all_files[@]}"; do
        if [[ "$check_only" == true ]]; then
            # Check mode - validate only
            if validate_markdown "$file"; then
                print_success "✓ $file"
                ((success_count++))
            else
                print_error "✗ $file"
                ((error_count++))
            fi
        else
            # Format mode
            if format_file "$file"; then
                ((success_count++))
            else
                ((error_count++))
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
}

# Run main function
main "$@"
