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

# Test statistics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

# Test markdown syntax and basic structure
validate_markdown_files() {
    log "Validating Markdown files..."
    
    local markdown_files
    mapfile -t markdown_files < <(find "$PROJECT_ROOT" -name "*.md" -type f -not -path "*/.git/*")
    
    for markdown_file in "${markdown_files[@]}"; do
        ((TESTS_RUN++))
        local file_name=$(basename "$markdown_file")
        
        # Check for basic markdown structure (headers)
        if grep -q "^#" "$markdown_file"; then
            success "Markdown structure valid: $file_name"
        else
            warning "No headers found in: $file_name"
        fi
        
        # Check file is not empty
        ((TESTS_RUN++))
        if [[ -s "$markdown_file" ]]; then
            success "File not empty: $file_name"
        else
            error "Empty file: $file_name"
        fi
    done
}

# Validate key documentation exists
validate_key_files() {
    log "Validating key documentation files..."
    
    local key_files=("README.md" "CLAUDE.md")
    
    for file in "${key_files[@]}"; do
        ((TESTS_RUN++))
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            success "$file exists"
        else
            error "$file missing"
        fi
    done
}

# Validate installation documentation
validate_installation_docs() {
    log "Validating installation documentation..."
    
    ((TESTS_RUN++))
    if grep -q "chezmoi.*init\|curl.*install" "$PROJECT_ROOT/README.md" 2>/dev/null; then
        success "Installation methods documented in README"
    else
        warning "Installation methods not clearly documented in README"
    fi
    
    ((TESTS_RUN++))
    if [[ -f "$PROJECT_ROOT/install" ]]; then
        success "Install script exists"
    else
        error "Install script missing"
    fi
}

# Validate CLAUDE.md content
validate_claude_md() {
    log "Validating CLAUDE.md content..."
    
    local claude_md="$PROJECT_ROOT/CLAUDE.md"
    if [[ ! -f "$claude_md" ]]; then
        error "CLAUDE.md not found"
        return 1
    fi
    
    # Check for key commands
    local commands=("chezmoi" "brewbundle" "zprofiler")
    for cmd in "${commands[@]}"; do
        ((TESTS_RUN++))
        if grep -q "$cmd" "$claude_md"; then
            success "Command '$cmd' documented in CLAUDE.md"
        else
            warning "Command '$cmd' not mentioned in CLAUDE.md"
        fi
    done
}

# Generate summary
generate_summary() {
    echo
    log "Documentation Validation Summary"
    echo "================================="
    echo "Total Tests: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    local success_rate
    if [[ $TESTS_RUN -gt 0 ]]; then
        success_rate=$(( TESTS_PASSED * 100 / TESTS_RUN ))
        echo "Success Rate: ${success_rate}%"
    fi
    
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
    
    # Run validation tests
    validate_key_files
    validate_markdown_files
    validate_installation_docs
    validate_claude_md
    
    # Generate summary
    generate_summary
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi