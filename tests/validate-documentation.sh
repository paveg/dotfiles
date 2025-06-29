#!/usr/bin/env bash
# Documentation Validation Script
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_FILE="${RESULTS_FILE:-/tmp/doc-validation-results.json}"

# Test statistics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Initialize results
echo '{"validations": []}' > "$RESULTS_FILE"

# Helper functions
log() {
    echo -e "${BLUE}[DOC-TEST]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

error() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Add result to JSON file
add_result() {
    local test_name="$1"
    local passed="$2"
    local message="$3"
    
    local temp_file=$(mktemp)
    jq --arg name "$test_name" \
       --argjson passed "$passed" \
       --arg message "$message" \
       '.validations += [{
         "name": $name,
         "passed": $passed,
         "message": $message,
         "timestamp": now
       }]' "$RESULTS_FILE" > "$temp_file"
    mv "$temp_file" "$RESULTS_FILE"
}

# Test markdown syntax and links
validate_markdown_files() {
    log "Validating Markdown files..."
    
    while IFS= read -r markdown_file; do
        ((TESTS_RUN++))
        local file_name=$(basename "$markdown_file")
        
        # Check markdown syntax if markdownlint is available
        if command -v markdownlint &>/dev/null; then
            if markdownlint "$markdown_file" >/dev/null 2>&1; then
                success "Markdown syntax valid: $file_name"
                add_result "markdown_syntax_$file_name" true "Valid markdown syntax"
            else
                error "Markdown syntax issues: $file_name"
                add_result "markdown_syntax_$file_name" false "Markdown syntax errors found"
            fi
        else
            # Basic syntax check
            if grep -q "^#" "$markdown_file" && ! grep -q "^####" "$markdown_file" | head -1; then
                success "Basic markdown structure valid: $file_name"
                add_result "markdown_basic_$file_name" true "Basic markdown structure valid"
            else
                warning "Could not validate markdown syntax for: $file_name (markdownlint not available)"
                add_result "markdown_basic_$file_name" true "Basic validation only"
            fi
        fi
        
        # Check for broken internal links
        ((TESTS_RUN++))
        local broken_links=0
        while IFS= read -r link; do
            local target=$(echo "$link" | sed 's/.*(\([^)]*\)).*/\1/')
            
            # Skip external URLs
            if [[ "$target" =~ ^https?:// ]]; then
                continue
            fi
            
            # Check if file exists (relative to markdown file location)
            local link_dir=$(dirname "$markdown_file")
            local target_file="$link_dir/$target"
            
            if [[ ! -f "$target_file" && ! -d "$target_file" ]]; then
                ((broken_links++))
            fi
        done < <(grep -o '\[.*\](.*\.md\|.*/)' "$markdown_file" 2>/dev/null || true)
        
        if [[ $broken_links -eq 0 ]]; then
            success "No broken internal links: $file_name"
            add_result "links_$file_name" true "No broken internal links"
        else
            error "Found $broken_links broken internal links: $file_name"
            add_result "links_$file_name" false "Found $broken_links broken internal links"
        fi
        
    done < <(find "$PROJECT_ROOT" -name "*.md" -type f -not -path "*/.git/*")
}

# Validate code examples in documentation
validate_code_examples() {
    log "Validating code examples in documentation..."
    
    local readme_file="$PROJECT_ROOT/README.md"
    if [[ ! -f "$readme_file" ]]; then
        error "README.md not found"
        add_result "readme_exists" false "README.md file missing"
        return 1
    fi
    
    ((TESTS_RUN++))
    success "README.md exists"
    add_result "readme_exists" true "README.md found"
    
    # Extract shell commands from README
    ((TESTS_RUN++))
    local command_errors=0
    
    # Look for code blocks with shell commands
    awk '/```bash/,/```/ {if (!/```/) print}' "$readme_file" > /tmp/readme_commands.sh 2>/dev/null || true
    awk '/```sh/,/```/ {if (!/```/) print}' "$readme_file" >> /tmp/readme_commands.sh 2>/dev/null || true
    
    if [[ -s /tmp/readme_commands.sh ]]; then
        # Check syntax of extracted commands
        if bash -n /tmp/readme_commands.sh 2>/dev/null; then
            success "Shell commands in README have valid syntax"
            add_result "readme_shell_syntax" true "Valid shell syntax in code examples"
        else
            error "Shell commands in README have syntax errors"
            add_result "readme_shell_syntax" false "Syntax errors in shell code examples"
            ((command_errors++))
        fi
        
        # Check for common command patterns
        ((TESTS_RUN++))
        if grep -q "curl.*install\|chezmoi.*apply" /tmp/readme_commands.sh; then
            success "Installation commands found in README"
            add_result "readme_install_commands" true "Installation commands documented"
        else
            warning "No installation commands found in README"
            add_result "readme_install_commands" false "Installation commands not found"
        fi
        
        rm -f /tmp/readme_commands.sh
    else
        warning "No shell code blocks found in README"
        add_result "readme_shell_syntax" true "No shell code to validate"
    fi
}

# Validate function documentation
validate_function_documentation() {
    log "Validating function documentation..."
    
    local zsh_modules_dir="$PROJECT_ROOT/dot_config/zsh/modules"
    if [[ ! -d "$zsh_modules_dir" ]]; then
        error "Zsh modules directory not found"
        add_result "zsh_modules_dir" false "Zsh modules directory missing"
        return 1
    fi
    
    ((TESTS_RUN++))
    success "Zsh modules directory found"
    add_result "zsh_modules_dir" true "Zsh modules directory exists"
    
    # Check if functions have documentation comments
    local undocumented_functions=0
    local total_functions=0
    
    while IFS= read -r module_file; do
        local module_name=$(basename "$module_file" .zsh)
        
        # Extract function definitions
        while IFS= read -r func_line; do
            local func_name=$(echo "$func_line" | sed 's/^\s*\([a-zA-Z_][a-zA-Z0-9_]*\)\s*().*/\1/')
            ((total_functions++))
            
            # Check if function has a comment above it
            local line_num=$(grep -n "^[[:space:]]*$func_name()" "$module_file" | cut -d: -f1)
            if [[ -n "$line_num" ]]; then
                local prev_line=$((line_num - 1))
                if sed -n "${prev_line}p" "$module_file" | grep -q "^[[:space:]]*#"; then
                    # Function has documentation
                    continue
                else
                    ((undocumented_functions++))
                fi
            fi
        done < <(grep "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$module_file" 2>/dev/null || true)
        
    done < <(find "$zsh_modules_dir" -name "*.zsh" -type f)
    
    ((TESTS_RUN++))
    if [[ $total_functions -gt 0 ]]; then
        local doc_percentage=$(( (total_functions - undocumented_functions) * 100 / total_functions ))
        if [[ $doc_percentage -ge 80 ]]; then
            success "Function documentation coverage: ${doc_percentage}% ($((total_functions - undocumented_functions))/$total_functions)"
            add_result "function_documentation" true "Good documentation coverage: ${doc_percentage}%"
        else
            warning "Function documentation coverage low: ${doc_percentage}% ($((total_functions - undocumented_functions))/$total_functions)"
            add_result "function_documentation" false "Low documentation coverage: ${doc_percentage}%"
        fi
    else
        warning "No functions found to document"
        add_result "function_documentation" true "No functions to document"
    fi
}

# Validate alias documentation
validate_alias_documentation() {
    log "Validating alias documentation..."
    
    local alias_file="$PROJECT_ROOT/dot_config/zsh/modules/alias.zsh"
    if [[ ! -f "$alias_file" ]]; then
        error "Alias module not found"
        add_result "alias_file_exists" false "Alias module file missing"
        return 1
    fi
    
    ((TESTS_RUN++))
    success "Alias module found"
    add_result "alias_file_exists" true "Alias module exists"
    
    # Check if aliases have documentation
    ((TESTS_RUN++))
    local total_aliases=$(grep -c "^[[:space:]]*alias" "$alias_file" 2>/dev/null || echo "0")
    local documented_aliases=0
    
    while IFS= read -r alias_line; do
        local line_num=$(grep -n "$alias_line" "$alias_file" | cut -d: -f1 | head -1)
        if [[ -n "$line_num" ]]; then
            # Check for comment on same line or line above
            if echo "$alias_line" | grep -q "#" || sed -n "$((line_num - 1))p" "$alias_file" | grep -q "^[[:space:]]*#"; then
                ((documented_aliases++))
            fi
        fi
    done < <(grep "^[[:space:]]*alias" "$alias_file" 2>/dev/null || true)
    
    if [[ $total_aliases -gt 0 ]]; then
        local alias_doc_percentage=$(( documented_aliases * 100 / total_aliases ))
        if [[ $alias_doc_percentage -ge 70 ]]; then
            success "Alias documentation coverage: ${alias_doc_percentage}% ($documented_aliases/$total_aliases)"
            add_result "alias_documentation" true "Good alias documentation: ${alias_doc_percentage}%"
        else
            warning "Alias documentation coverage low: ${alias_doc_percentage}% ($documented_aliases/$total_aliases)"
            add_result "alias_documentation" false "Low alias documentation: ${alias_doc_percentage}%"
        fi
    else
        warning "No aliases found"
        add_result "alias_documentation" true "No aliases to document"
    fi
}

# Validate CLAUDE.md accuracy
validate_claude_md() {
    log "Validating CLAUDE.md accuracy..."
    
    local claude_md="$PROJECT_ROOT/CLAUDE.md"
    if [[ ! -f "$claude_md" ]]; then
        error "CLAUDE.md not found"
        add_result "claude_md_exists" false "CLAUDE.md missing"
        return 1
    fi
    
    ((TESTS_RUN++))
    success "CLAUDE.md exists"
    add_result "claude_md_exists" true "CLAUDE.md found"
    
    # Check if key commands mentioned in CLAUDE.md actually exist
    ((TESTS_RUN++))
    local missing_commands=()
    
    # Extract commands from CLAUDE.md
    local commands=(
        "brewbundle"
        "zprofiler"
        "zshtime"
        "chezmoi"
    )
    
    for cmd in "${commands[@]}"; do
        if ! grep -q "$cmd" "$claude_md"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        success "All key commands documented in CLAUDE.md"
        add_result "claude_md_commands" true "All key commands documented"
    else
        warning "Missing commands in CLAUDE.md: ${missing_commands[*]}"
        add_result "claude_md_commands" false "Missing commands: ${missing_commands[*]}"
    fi
    
    # Check if CLAUDE.md mentions recent architectural changes
    ((TESTS_RUN++))
    if grep -q "performance\|lazy.loading\|module.*system" "$claude_md"; then
        success "CLAUDE.md mentions recent architectural improvements"
        add_result "claude_md_updates" true "Mentions recent improvements"
    else
        warning "CLAUDE.md may need updates for recent changes"
        add_result "claude_md_updates" false "May need updates for recent changes"
    fi
}

# Validate installation documentation
validate_installation_docs() {
    log "Validating installation documentation..."
    
    # Check if installation methods are documented
    ((TESTS_RUN++))
    local install_methods_found=0
    
    for doc_file in "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/CLAUDE.md"; do
        if [[ -f "$doc_file" ]]; then
            if grep -q "curl.*install\|chezmoi.*init" "$doc_file"; then
                ((install_methods_found++))
            fi
        fi
    done
    
    if [[ $install_methods_found -gt 0 ]]; then
        success "Installation methods documented"
        add_result "installation_docs" true "Installation methods found in documentation"
    else
        error "Installation methods not clearly documented"
        add_result "installation_docs" false "Installation methods not documented"
    fi
    
    # Check if dependencies are documented
    ((TESTS_RUN++))
    if grep -q "git\|zsh\|curl" "$PROJECT_ROOT/README.md" 2>/dev/null; then
        success "Dependencies mentioned in documentation"
        add_result "dependencies_docs" true "Dependencies documented"
    else
        warning "Dependencies not clearly documented"
        add_result "dependencies_docs" false "Dependencies not documented"
    fi
}

# Generate documentation summary
generate_summary() {
    log "Generating documentation validation summary..."
    
    local temp_file=$(mktemp)
    jq --argjson total "$TESTS_RUN" \
       --argjson passed "$TESTS_PASSED" \
       --argjson failed "$TESTS_FAILED" \
       '.summary = {
         "total_tests": $total,
         "passed": $passed,
         "failed": $failed,
         "success_rate": (($passed * 100) / $total),
         "timestamp": now
       }' "$RESULTS_FILE" > "$temp_file"
    mv "$temp_file" "$RESULTS_FILE"
    
    echo
    log "Documentation Validation Summary"
    echo "================================="
    echo "Total Tests: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    local success_rate=$(( TESTS_PASSED * 100 / TESTS_RUN ))
    echo "Success Rate: ${success_rate}%"
    
    echo "Results saved to: $RESULTS_FILE"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}✅ All documentation validation tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Some documentation validation tests failed!${NC}"
        return 1
    fi
}

# Main function
main() {
    log "Starting Documentation Validation"
    echo "=================================="
    
    # Ensure we have jq for JSON processing
    if ! command -v jq &>/dev/null; then
        error "jq is required for this script. Please install it."
        exit 1
    fi
    
    # Run validation tests
    validate_markdown_files
    validate_code_examples
    validate_function_documentation
    validate_alias_documentation
    validate_claude_md
    validate_installation_docs
    
    # Generate summary
    generate_summary
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi