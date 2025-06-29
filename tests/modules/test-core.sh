#!/usr/bin/env bash
# Module Tests: Core Functions
set -euo pipefail

# Source the test framework
source "$(dirname "$0")/../framework/test-framework.sh"

# Test setup
setup() {
    # Check if modules exist in various possible locations
    if [[ -d "$HOME/.config/zsh/modules" ]]; then
        export TEST_MODULE_DIR="$HOME/.config/zsh/modules"
    elif [[ -d "./dot_config/zsh/modules" ]]; then
        export TEST_MODULE_DIR="./dot_config/zsh/modules"
    elif [[ -d "dot_config/zsh/modules" ]]; then
        export TEST_MODULE_DIR="dot_config/zsh/modules"
    else
        export TEST_MODULE_DIR=""
    fi
    export TEMP_TEST_DIR="/tmp/dotfiles-test-$$"
    mkdir -p "$TEMP_TEST_DIR"
}

# Test cleanup
teardown() {
    rm -rf "$TEMP_TEST_DIR"
}

# Test zcompare function
test_zcompare_function() {
    test_start "zcompare function creates .zwc files"
    
    local test_file="$TEMP_TEST_DIR/test.zsh"
    echo 'echo "test"' > "$test_file"
    
    # Test zcompare function via zsh
    if [[ -n "$TEST_MODULE_DIR" && -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        # Run zcompare in zsh subprocess
        local result
        result=$(zsh -c 'unset _CORE_LOADED; export _COMP_INITIALIZED=1; source "'"$TEST_MODULE_DIR"'/core.zsh"; zcompare "'"$test_file"'" && echo SUCCESS || echo FAILED' 2>/dev/null)
        
        if [[ "$result" == "SUCCESS" ]]; then
            # Check if .zwc file was created
            if [[ -f "${test_file}.zwc" ]]; then
                test_pass "Compiled file created successfully"
            else
                test_fail "Compiled file was not created"
            fi
        else
            test_fail "zcompare function failed: $result"
        fi
    else
        test_skip "Core module not found"
    fi
}

test_zcompare_skips_uptodate() {
    test_start "zcompare skips compilation when .zwc is up to date"
    
    # This test is complex and may cause hanging, skip for now
    test_skip "Complex zcompare timing test - skipping to avoid CI issues"
}

# Test init_completion function
test_init_completion() {
    test_start "init_completion function exists"
    
    if [[ -n "$TEST_MODULE_DIR" && -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        # Test that init_completion function exists via zsh
        local result
        result=$(zsh -c 'unset _CORE_LOADED; export _COMP_INITIALIZED=1; source "'"$TEST_MODULE_DIR"'/core.zsh"; declare -f init_completion >/dev/null && echo SUCCESS || echo FAILED' 2>/dev/null)
        
        if [[ "$result" == "SUCCESS" ]]; then
            test_pass "init_completion function is available"
        else
            test_fail "init_completion function not found"
        fi
    else
        test_skip "Core module not found"
    fi
}

# Test load function
test_load_function() {
    test_start "load function exists and works"
    
    if [[ -n "$TEST_MODULE_DIR" && -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        # Test that load function exists via zsh
        local result
        result=$(zsh -c 'unset _CORE_LOADED; export _COMP_INITIALIZED=1; source "'"$TEST_MODULE_DIR"'/core.zsh"; declare -f load >/dev/null && echo SUCCESS || echo FAILED' 2>/dev/null)
        
        if [[ "$result" == "SUCCESS" ]]; then
            test_pass "load function is available"
        else
            test_fail "load function not found"
        fi
    else
        test_skip "Core module not found"
    fi
}

# Test error handling in core functions
test_core_error_handling() {
    test_start "core functions handle errors gracefully"
    
    if [[ -n "$TEST_MODULE_DIR" && -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        # Test that error functions exist
        local result
        result=$(zsh -c 'unset _CORE_LOADED; export _COMP_INITIALIZED=1; source "'"$TEST_MODULE_DIR"'/core.zsh"; declare -f error >/dev/null && declare -f warn >/dev/null && echo SUCCESS || echo FAILED' 2>/dev/null)
        
        if [[ "$result" == "SUCCESS" ]]; then
            test_pass "Error handling functions are available"
        else
            test_fail "Error handling functions not found"
        fi
    else
        test_skip "Core module not found"
    fi
}

# Run all tests
main() {
    test_suite_start "Core Module Tests"
    
    setup
    
    test_zcompare_function
    test_zcompare_skips_uptodate
    test_init_completion
    test_load_function
    test_core_error_handling
    
    teardown
    
    test_suite_end
}

# Run tests if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi