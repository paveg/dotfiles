#!/usr/bin/env bash
# TDD Test Runner for dotfiles
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
PASSED=0
FAILED=0

# Test helper functions
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -n "Running: $test_name ... "

    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED++))
        return 1
    fi
}

# Test Suite 1: Core Requirements
echo "=== Test Suite 1: Core Requirements ==="

run_test "Zsh is available" "command -v zsh"
run_test "Git is available" "command -v git"
run_test "Curl is available" "command -v curl"

# Test Suite 2: Directory Structure
echo -e "\n=== Test Suite 2: Directory Structure ==="

run_test "zsh.d directory exists" "test -d zsh.d"
run_test "modules directory exists" "test -d zsh.d/modules"
run_test "git directory exists" "test -d git"
run_test "nvim directory exists" "test -d nvim"

# Test Suite 3: Essential Files
echo -e "\n=== Test Suite 3: Essential Files ==="

run_test ".zshrc exists" "test -f zsh.d/.zshrc"
run_test ".zshenv exists" "test -f zsh.d/.zshenv"
run_test ".zprofile exists" "test -f zsh.d/.zprofile"
run_test "install.sh exists" "test -f install.sh"

# Test Suite 4: Zsh Syntax Validation
echo -e "\n=== Test Suite 4: Zsh Syntax Validation ==="

run_test ".zshrc syntax" "zsh -n zsh.d/.zshrc"
run_test ".zshenv syntax" "zsh -n zsh.d/.zshenv"
run_test ".zprofile syntax" "zsh -n zsh.d/.zprofile"

for module in zsh.d/modules/*.zsh; do
    if [[ -f "$module" ]]; then
        module_name=$(basename "$module")
        run_test "module $module_name syntax" "zsh -n $module"
    fi
done

# Test Suite 5: Installation Components
echo -e "\n=== Test Suite 5: Installation Components ==="

run_test "install.sh is executable" "test -x install.sh"
run_test "format_zsh.sh exists" "test -f scripts/format_zsh.sh"
run_test "format_zsh.sh is executable" "test -x scripts/format_zsh.sh"

# Summary
echo -e "\n=== Test Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [[ $FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi
