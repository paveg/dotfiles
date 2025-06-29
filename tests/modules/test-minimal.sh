#!/usr/bin/env bash
# Minimal Module Test - Absolutely minimal for CI reliability
set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Minimal Module Tests ==="

# Test that essential files exist
# Try different possible locations for the module directory
# Priority: Applied test directory (CI) > Source directory > Home directory
if [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME/.config/zsh/modules" ]]; then
    MODULE_DIR="$TEST_HOME/.config/zsh/modules"
    echo "Using applied test directory: $MODULE_DIR"
elif [[ -d "$HOME/.config/zsh/modules" ]]; then
    MODULE_DIR="$HOME/.config/zsh/modules"
    echo "Using home directory: $MODULE_DIR"
elif [[ -d "./dot_config/zsh/modules" ]]; then
    MODULE_DIR="./dot_config/zsh/modules"
    echo "Using relative source directory: $MODULE_DIR"
elif [[ -d "dot_config/zsh/modules" ]]; then
    MODULE_DIR="dot_config/zsh/modules"
    echo "Using source directory: $MODULE_DIR"
else
    echo -e "${RED}✗ Module directory not found. Checked:${NC}"
    echo "  - TEST_HOME: ${TEST_HOME:-unset}"
    [[ -n "${TEST_HOME:-}" ]] && echo "  - $TEST_HOME/.config/zsh/modules"
    echo "  - $HOME/.config/zsh/modules"
    echo "  - ./dot_config/zsh/modules"
    echo "  - dot_config/zsh/modules"
    echo "  - Current directory: $(pwd)"
    echo "  - Available directories:"
    find . -name "modules" -type d 2>/dev/null || echo "    No modules directories found"
    [[ -n "${TEST_HOME:-}" ]] && find "$TEST_HOME" -name "modules" -type d 2>/dev/null || true
    exit 1
fi

# Check essential files
ESSENTIAL_FILES=("core.zsh" "path.zsh" "platform.zsh")
MISSING_FILES=()

for file in "${ESSENTIAL_FILES[@]}"; do
    if [[ ! -f "$MODULE_DIR/$file" ]]; then
        MISSING_FILES+=("$file")
    fi
done

if [[ ${#MISSING_FILES[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ All essential module files exist${NC}"
    echo "Tests run: 1"
    echo "Passed: 1"
    echo "Failed: 0"
    echo "Skipped: 0"
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Missing files: ${MISSING_FILES[*]}${NC}"
    echo "Tests run: 1"
    echo "Passed: 0"
    echo "Failed: 1"
    echo "Skipped: 0"
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi