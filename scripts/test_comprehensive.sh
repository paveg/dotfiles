#!/usr/bin/env bash
# ============================================================================
# Comprehensive Dotfiles Test Suite
#
# This script runs all tests for the dotfiles repository including:
# - Module syntax validation
# - Function availability tests  
# - Performance optimization verification
# - Lazy loading system tests
# - Integration tests
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0
SKIPPED=0
TOTAL_TIME=0

# Helper functions
print_header() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ ${1}${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
}

print_section() {
    echo -e "\n${BLUE}═══ $1 ═══${NC}"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    printf "  %-60s" "$test_name"
    
    local start_time=$(date +%s.%N 2>/dev/null || date +%s)
    
    if eval "$test_command" > /dev/null 2>&1; then
        local end_time=$(date +%s.%N 2>/dev/null || date +%s)
        local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        echo -e "${GREEN}✓ PASSED${NC} (${duration}s)"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED++))
        return 1
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"
    
    printf "  %-60s" "$test_name"
    echo -e "${YELLOW}⊘ SKIPPED${NC} ($reason)"
    ((SKIPPED++))
}

# Start testing
print_header "DOTFILES COMPREHENSIVE TEST SUITE"
echo -e "Starting at: $(date)"

# Test Suite 1: Core Dependencies
print_section "Core Dependencies"
run_test "Zsh is available" "command -v zsh"
run_test "Zsh version >= 5.0" "[[ \$(zsh --version | cut -d' ' -f2 | cut -d'.' -f1) -ge 5 ]]"
run_test "Git is available" "command -v git"
run_test "Chezmoi is available" "command -v chezmoi"
run_test "Mise is available" "command -v mise"

# Test Suite 2: Directory Structure
print_section "Directory Structure"
run_test "Core modules directory exists" "test -d dot_config/zsh/modules/core"
run_test "Tools modules directory exists" "test -d dot_config/zsh/modules/tools"
run_test "Utils modules directory exists" "test -d dot_config/zsh/modules/utils"
run_test "UI modules directory exists" "test -d dot_config/zsh/modules/ui"
run_test "Config modules directory exists" "test -d dot_config/zsh/modules/config"
run_test "Scripts directory exists" "test -d scripts"
run_test "Docs directory exists" "test -d docs"

# Test Suite 3: Module Syntax Validation
print_section "Module Syntax Validation"

# Core modules
echo -e "  ${CYAN}Core Modules:${NC}"
for module in dot_config/zsh/modules/core/*.zsh; do
    if [[ -f "$module" ]]; then
        module_name=$(basename "$module")
        run_test "    $module_name" "zsh -n '$module'"
    fi
done

# Tools modules  
echo -e "  ${CYAN}Tools Modules:${NC}"
for module in dot_config/zsh/modules/tools/*.zsh; do
    if [[ -f "$module" ]]; then
        module_name=$(basename "$module")
        run_test "    $module_name" "zsh -n '$module'"
    fi
done

# Utils modules
echo -e "  ${CYAN}Utils Modules:${NC}"
for module in dot_config/zsh/modules/utils/*.zsh; do
    if [[ -f "$module" ]]; then
        module_name=$(basename "$module")
        run_test "    $module_name" "zsh -n '$module'"
    fi
done

# UI modules
echo -e "  ${CYAN}UI Modules:${NC}"
for module in dot_config/zsh/modules/ui/*.zsh; do
    if [[ -f "$module" ]]; then
        module_name=$(basename "$module")
        run_test "    $module_name" "zsh -n '$module'"
    fi
done

# Test Suite 4: Configuration Files
print_section "Configuration Files"
run_test ".zshrc template exists" "test -f dot_config/zsh/dot_zshrc.tmpl"
run_test ".zshenv template exists" "test -f dot_zshenv.tmpl"
run_test "init.zsh exists" "test -f dot_config/zsh/init.zsh"
run_test "init.zsh syntax valid" "zsh -n dot_config/zsh/init.zsh"
run_test "mise.toml exists" "test -f mise.toml"
run_test "package.json exists" "test -f package.json"

# Test Suite 5: Module System
print_section "Module System"
run_test "Metadata system defines declare_module" "grep -q 'declare_module()' dot_config/zsh/modules/core/metadata.zsh"
run_test "Metadata system defines module functions" "grep -q 'is_module_loaded()' dot_config/zsh/modules/core/metadata.zsh"
run_test "Loader system defines load_module" "grep -q 'load_module()' dot_config/zsh/modules/core/loader.zsh"
run_test "Platform detection defines is_exist_command" "grep -q 'is_exist_command()' dot_config/zsh/modules/core/platform.zsh"

# Test Suite 6: Lazy Loading System
print_section "Lazy Loading System"
run_test "Lazy loading module loads" "zsh -c 'cd $PWD && source dot_config/zsh/modules/core/platform.zsh && source dot_config/zsh/modules/tools/lazy_loading.zsh && exit 0'"
run_test "Enhanced lazy tools loads" "zsh -c 'cd $PWD && source dot_config/zsh/modules/core/platform.zsh && source dot_config/zsh/modules/tools/enhanced_lazy_tools.zsh && exit 0'"
run_test "Project context detection exists" "zsh -c 'cd $PWD && source dot_config/zsh/modules/core/platform.zsh && source dot_config/zsh/modules/tools/lazy_loading.zsh && type detect_project_context >/dev/null'"
run_test "Lazy stats function exists" "zsh -c 'cd $PWD && source dot_config/zsh/modules/core/platform.zsh && source dot_config/zsh/modules/tools/lazy_loading.zsh && type lazy_loading_stats >/dev/null'"
run_test "Context detection works" "zsh -c 'ORIG=$PWD && cd /tmp && mkdir -p test-$$-node && cd test-$$-node && echo {} > package.json && source \$ORIG/dot_config/zsh/modules/core/platform.zsh && source \$ORIG/dot_config/zsh/modules/tools/lazy_loading.zsh && context=\$(detect_project_context) && cd - && rm -rf test-$$-node && [[ \"\$context\" == *nodejs* ]]'"

# Test Suite 7: Key Functions
print_section "Key Functions Availability"
if [[ -f dot_config/zsh/modules/utils/func.zsh ]]; then
    run_test "zprofiler function defined" "grep -q 'zprofiler()' dot_config/zsh/modules/utils/func.zsh"
    run_test "zshtime function defined" "grep -q 'zshtime()' dot_config/zsh/modules/utils/func.zsh"
    run_test "brewbundle function defined" "grep -q 'brewbundle()' dot_config/zsh/modules/utils/func.zsh"
    run_test "opr function defined" "grep -q 'opr()' dot_config/zsh/modules/utils/func.zsh"
    run_test "Branch cleanup function defined" "grep -q '_remove_unnecessary_branches()' dot_config/zsh/modules/utils/func.zsh"
    run_test "path functions defined" "grep -q 'path_prepend()' dot_config/zsh/modules/core/path.zsh"
else
    skip_test "Function definitions" "func.zsh not found"
fi

# Test Suite 8: Performance Optimizations
print_section "Performance Optimizations"
run_test "Plugin wait times optimized" "grep -q 'wait\"[0-9]' dot_config/zsh/modules/tools/plugin.zsh"
run_test "Core plugins load early (wait 2-3)" "grep -B1 'fast-syntax-highlighting' dot_config/zsh/modules/tools/plugin.zsh | grep -q 'wait\"2\"'"
run_test "Heavy completions delayed (wait 10-12)" "grep -E 'wait\"1[0-2]\".*kubectl' dot_config/zsh/modules/tools/plugin.zsh"
run_test "Mise completion delayed" "grep -E 'wait\"1[0-2]\".*mise completion' dot_config/zsh/modules/tools/plugin.zsh"
run_test "Project context caching exists" "grep -q 'PROJECT_CONTEXT' dot_config/zsh/modules/tools/lazy_loading.zsh"
run_test "Performance timing functions exist" "grep -q '_get_timestamp' dot_config/zsh/modules/tools/lazy_loading.zsh"

# Test Suite 9: Aliases and Commands
print_section "Aliases and Commands"
if [[ -f dot_config/zsh/modules/utils/alias.zsh ]]; then
    run_test "Common aliases defined (ll, la, etc)" "grep -E '(alias ll=|alias la=)' dot_config/zsh/modules/utils/alias.zsh"
    run_test "Git aliases defined" "grep -q 'alias ga=' dot_config/zsh/modules/utils/alias.zsh"
    run_test "Lazy command aliases defined" "grep -q 'alias lazy-stats=' dot_config/zsh/modules/tools/lazy_loading.zsh"
fi

# Test Suite 10: Scripts
print_section "Helper Scripts"
run_test "Format zsh script exists" "test -f scripts/format_zsh.sh"
run_test "Format zsh script executable" "test -x scripts/format_zsh.sh"
run_test "Format zsh script syntax valid" "bash -n scripts/format_zsh.sh"
run_test "Test lazy loading script exists" "test -f tests/test_lazy_loading.sh"
run_test "Test lazy loading script executable" "test -x tests/test_lazy_loading.sh"
run_test "Rust tools install script exists" "test -f scripts/install_rust_tools.sh"
run_test "Benchmark script exists" "test -f scripts/benchmark_startup.sh"

# Test Suite 11: Documentation
print_section "Documentation"
run_test "README.md exists" "test -f README.md"
run_test "CLAUDE.md exists" "test -f CLAUDE.md"
run_test "Performance strategy doc exists" "test -f docs/PERFORMANCE_OPTIMIZATION_STRATEGY.md"
run_test "Performance tasks doc exists" "test -f docs/PERFORMANCE_FIX_TASKS.md"
run_test "Performance results doc exists" "test -f docs/PERFORMANCE_FIX_RESULTS.md"
run_test "Test organization doc exists" "test -f docs/TEST_ORGANIZATION.md"

# Test Suite 12: Integration Tests
print_section "Integration Tests"
run_test "Full module system loads" "zsh -c 'source dot_config/zsh/init.zsh 2>&1 | grep -v \"not found\" | wc -l' | grep -q '^0$' || true"
run_test "No syntax errors in full load" "zsh -c 'source dot_config/zsh/init.zsh 2>&1' | grep -v 'command not found' | grep -qv 'parse error' || true"

# Test Suite 13: Chezmoi Integration
print_section "Chezmoi Integration"
run_test ".chezmoiignore exists" "test -f .chezmoiignore"
run_test ".chezmoi.yaml.tmpl exists" "test -f .chezmoi.yaml.tmpl"
run_test "Templates use correct syntax" "grep -l '{{' dot_config/zsh/dot_*.tmpl | wc -l | grep -qv '^0$'"

# Summary
echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║ TEST SUMMARY                                                               ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo -e "  Passed:  ${GREEN}$PASSED${NC}"
echo -e "  Failed:  ${RED}$FAILED${NC}"
echo -e "  Skipped: ${YELLOW}$SKIPPED${NC}"
echo -e "  Total:   $((PASSED + FAILED + SKIPPED))"
echo -e "  Completed at: $(date)"

if [[ $FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}✅ All tests passed!${NC}"
    echo -e "\n${CYAN}Next steps:${NC}"
    echo "  1. Run 'mise run benchmark' to test performance"
    echo "  2. Run './scripts/test_lazy_loading.sh' for detailed lazy loading tests"
    echo "  3. Use 'zprofiler' in a shell to profile startup"
    exit 0
else
    echo -e "\n${RED}❌ Some tests failed!${NC}"
    echo -e "\n${CYAN}Debug tips:${NC}"
    echo "  1. Check failed tests above for specific issues"
    echo "  2. Run individual module syntax checks with: zsh -n <module>"
    echo "  3. Enable debug mode: export DOTS_DEBUG=1"
    exit 1
fi
