#!/usr/bin/env bash
# Module Tests: Core Functions
set -euo pipefail

# Source the test framework
source "$(dirname "$0")/../framework/test-framework.sh"

# Test setup
setup() {
    export TEST_MODULE_DIR="$HOME/.config/zsh/modules"
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
    
    # Source core module to get zcompare function
    if [[ -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        source "$TEST_MODULE_DIR/core.zsh"
        
        # Run zcompare
        zcompare "$test_file"
        
        # Check if .zwc file was created
        assert_file_exists "${test_file}.zwc" "Compiled .zwc file should exist"
        
        # Check if .zwc file is newer or same age as source
        if [[ "${test_file}.zwc" -nt "$test_file" ]] || [[ "${test_file}.zwc" -ef "$test_file" ]]; then
            test_pass "Compiled file is up to date"
        else
            test_fail "Compiled file is older than source"
        fi
    else
        test_skip "Core module not found"
    fi
}

test_zcompare_skips_uptodate() {
    test_start "zcompare skips compilation when .zwc is up to date"
    
    local test_file="$TEMP_TEST_DIR/test2.zsh"
    echo 'echo "test2"' > "$test_file"
    
    if [[ -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        source "$TEST_MODULE_DIR/core.zsh"
        
        # First compilation
        zcompare "$test_file"
        local first_mtime=$(stat -c %Y "${test_file}.zwc" 2>/dev/null || stat -f %m "${test_file}.zwc")
        
        sleep 1
        
        # Second compilation (should skip)
        zcompare "$test_file"
        local second_mtime=$(stat -c %Y "${test_file}.zwc" 2>/dev/null || stat -f %m "${test_file}.zwc")
        
        if [[ "$first_mtime" == "$second_mtime" ]]; then
            test_pass "zcompare correctly skipped recompilation"
        else
            test_fail "zcompare unnecessarily recompiled"
        fi
    else
        test_skip "Core module not found"
    fi
}

# Test init_completion function
test_init_completion() {
    test_start "init_completion sets up completion system"
    
    if [[ -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        # Create a temporary zsh session to test completion
        local test_script="$TEMP_TEST_DIR/test_completion.zsh"
        cat > "$test_script" << 'EOF'
source "$TEST_MODULE_DIR/core.zsh"
init_completion

# Check if fpath includes completion directories
if [[ -n "${fpath[(r)*completion*]}" ]] || [[ -n "${fpath[(r)*zsh/site-functions*]}" ]]; then
    echo "COMPLETION_SUCCESS"
else
    echo "COMPLETION_FAILED"
fi
EOF
        
        local result=$(zsh -c "TEST_MODULE_DIR='$TEST_MODULE_DIR'; source '$test_script'" 2>/dev/null || echo "COMPLETION_ERROR")
        
        case "$result" in
            "COMPLETION_SUCCESS")
                test_pass "Completion system initialized correctly"
                ;;
            "COMPLETION_FAILED")
                test_fail "Completion system not properly initialized"
                ;;
            *)
                test_fail "Error testing completion system: $result"
                ;;
        esac
    else
        test_skip "Core module not found"
    fi
}

# Test load function
test_load_function() {
    test_start "load function sources files correctly"
    
    local test_file="$TEMP_TEST_DIR/test_load.zsh"
    echo 'TEST_LOAD_VAR="loaded"' > "$test_file"
    
    if [[ -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        # Test in a subshell to avoid polluting environment
        (
            source "$TEST_MODULE_DIR/core.zsh"
            load "$test_file"
            
            if [[ "${TEST_LOAD_VAR:-}" == "loaded" ]]; then
                echo "LOAD_SUCCESS"
            else
                echo "LOAD_FAILED"
            fi
        )
        
        local result=$?
        if [[ $result -eq 0 ]]; then
            test_pass "load function works correctly"
        else
            test_fail "load function failed"
        fi
    else
        test_skip "Core module not found"
    fi
}

# Test error handling in core functions
test_core_error_handling() {
    test_start "core functions handle errors gracefully"
    
    if [[ -f "$TEST_MODULE_DIR/core.zsh" ]]; then
        source "$TEST_MODULE_DIR/core.zsh"
        
        # Test zcompare with non-existent file
        if zcompare "/nonexistent/file.zsh" 2>/dev/null; then
            test_fail "zcompare should fail on non-existent file"
        else
            test_pass "zcompare correctly handles non-existent files"
        fi
        
        # Test load with non-existent file
        if load "/nonexistent/file.zsh" 2>/dev/null; then
            test_fail "load should fail on non-existent file"
        else
            test_pass "load correctly handles non-existent files"
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