#!/usr/bin/env bash
# Documentation Validation Script
set -e

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
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

error() {
    echo -e "${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Main validation function
main() {
    log "Starting Documentation Validation"
    echo "=================================="
    
    # Test 1: Check README.md exists
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$PROJECT_ROOT/README.md" ]]; then
        success "README.md exists"
    else
        error "README.md missing"
    fi
    
    # Test 2: Check CLAUDE.md exists
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
        success "CLAUDE.md exists"
    else
        error "CLAUDE.md missing"
    fi
    
    # Test 3: Check README has installation instructions
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "chezmoi\|curl.*install" "$PROJECT_ROOT/README.md" 2>/dev/null; then
        success "Installation instructions found in README"
    else
        warning "Installation instructions not clearly found in README"
    fi
    
    # Test 4: Check CLAUDE.md has key commands
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "chezmoi" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null; then
        success "Key commands documented in CLAUDE.md"
    else
        warning "Key commands not found in CLAUDE.md"
    fi
    
    # Test 5: Check install script exists
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$PROJECT_ROOT/install" ]]; then
        success "Install script exists"
    else
        error "Install script missing"
    fi
    
    # Test 6: Check basic markdown files are not empty
    TESTS_RUN=$((TESTS_RUN + 1))
    local empty_files=0
    for file in "$PROJECT_ROOT"/*.md; do
        if [[ -f "$file" && ! -s "$file" ]]; then
            empty_files=$((empty_files + 1))
        fi
    done
    
    if [[ $empty_files -eq 0 ]]; then
        success "No empty markdown files found"
    else
        error "Found $empty_files empty markdown files"
    fi
    
    # Generate summary
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
        exit 0
    else
        echo -e "\n${RED}❌ $TESTS_FAILED documentation validation test(s) failed!${NC}"
        exit 1
    fi
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi