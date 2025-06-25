#!/usr/bin/env bash
# Minimal test suite - Start with the absolute basics
set -e

echo "=== Minimal Test Suite ==="

# Test 1: This script runs
echo "✓ Test script is running"

# Test 2: We're in the right directory
if [[ -d "zsh.d" ]]; then
    echo "✓ zsh.d directory exists"
else
    echo "✗ zsh.d directory not found"
    exit 1
fi

# Test 3: Critical files exist
if [[ -f "zsh.d/.zshrc" ]]; then
    echo "✓ .zshrc exists"
else
    echo "✗ .zshrc not found"
    exit 1
fi

echo ""
echo "=== All minimal tests passed! ==="
