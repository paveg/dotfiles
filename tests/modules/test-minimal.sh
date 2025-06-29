#!/usr/bin/env bash
# Minimal Module Test - Absolutely minimal for CI reliability
set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Minimal Module Tests ==="

# Test that essential files exist
if [[ -d "./dot_config/zsh/modules" ]]; then
    MODULE_DIR="./dot_config/zsh/modules"
elif [[ -d "$HOME/.config/zsh/modules" ]]; then
    MODULE_DIR="$HOME/.config/zsh/modules"
else
    echo -e "${RED}✗ Module directory not found${NC}"
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