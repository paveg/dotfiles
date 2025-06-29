#!/usr/bin/env bash
# Test Framework for Dotfiles
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Test statistics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_TEST=""
TEST_SUITE_NAME=""

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Test framework functions
test_suite_start() {
    TEST_SUITE_NAME="$1"
    echo -e "\n${BOLD}=== $TEST_SUITE_NAME ===${NC}"
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
}

test_suite_end() {
    echo -e "\n${BOLD}=== Test Suite Summary: $TEST_SUITE_NAME ===${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        return 1
    fi
}

test_start() {
    CURRENT_TEST="$1"
    ((TESTS_RUN++))
    echo -n "  Testing: $CURRENT_TEST ... "
}

test_pass() {
    local message="${1:-}"
    echo -e "${GREEN}PASS${NC}"
    if [[ -n "$message" ]]; then
        echo "    $message"
    fi
    ((TESTS_PASSED++))
}

test_fail() {
    local message="${1:-}"
    echo -e "${RED}FAIL${NC}"
    if [[ -n "$message" ]]; then
        echo "    $message"
    fi
    ((TESTS_FAILED++))
}

test_skip() {
    local message="${1:-}"
    echo -e "${YELLOW}SKIP${NC}"
    if [[ -n "$message" ]]; then
        echo "    $message"
    fi
    ((TESTS_SKIPPED++))
}

# Assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        test_fail "$message: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"
    
    if [[ "$expected" != "$actual" ]]; then
        return 0
    else
        test_fail "$message: both values are '$expected'"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"
    
    if [[ -f "$file" ]]; then
        return 0
    else
        test_fail "$message: $file"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local message="${2:-File should not exist}"
    
    if [[ ! -f "$file" ]]; then
        return 0
    else
        test_fail "$message: $file"
        return 1
    fi
}

assert_directory_exists() {
    local dir="$1"
    local message="${2:-Directory should exist}"
    
    if [[ -d "$dir" ]]; then
        return 0
    else
        test_fail "$message: $dir"
        return 1
    fi
}

assert_command_exists() {
    local command="$1"
    local message="${2:-Command should exist}"
    
    if command -v "$command" &>/dev/null; then
        return 0
    else
        test_fail "$message: $command"
        return 1
    fi
}

assert_string_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" =~ $needle ]]; then
        return 0
    else
        test_fail "$message: '$haystack' should contain '$needle'"
        return 1
    fi
}

assert_string_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"
    
    if [[ ! "$haystack" =~ $needle ]]; then
        return 0
    else
        test_fail "$message: '$haystack' should not contain '$needle'"
        return 1
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local command="$2"
    local message="${3:-Command should exit with expected code}"
    
    local actual_code=0
    eval "$command" &>/dev/null || actual_code=$?
    
    if [[ $actual_code -eq $expected_code ]]; then
        return 0
    else
        test_fail "$message: expected exit code $expected_code, got $actual_code"
        return 1
    fi
}

# Test utilities
run_in_temp_dir() {
    local command="$1"
    local temp_dir=$(mktemp -d)
    
    (
        cd "$temp_dir"
        eval "$command"
    )
    local result=$?
    
    rm -rf "$temp_dir"
    return $result
}

capture_output() {
    local command="$1"
    eval "$command" 2>&1
}

# Mock functions for testing
mock_command() {
    local command_name="$1"
    local mock_behavior="$2"
    
    eval "$command_name() { $mock_behavior; }"
}

unmock_command() {
    local command_name="$1"
    unset -f "$command_name" 2>/dev/null || true
}

# Environment setup for tests
setup_test_environment() {
    # Set up minimal test environment
    export TEST_MODE=1
    export CI_SKIP_PACKAGES=1
    
    # Create temporary test directories
    export TEST_HOME="/tmp/dotfiles-test-home-$$"
    export TEST_CONFIG_DIR="$TEST_HOME/.config"
    export TEST_ZSH_DIR="$TEST_CONFIG_DIR/zsh"
    
    mkdir -p "$TEST_HOME" "$TEST_CONFIG_DIR" "$TEST_ZSH_DIR"
    
    # Set test-specific variables
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
    export ZDOTDIR="$TEST_ZSH_DIR"
}

cleanup_test_environment() {
    # Clean up test environment
    rm -rf "$TEST_HOME" 2>/dev/null || true
    unset TEST_MODE CI_SKIP_PACKAGES TEST_HOME TEST_CONFIG_DIR TEST_ZSH_DIR
}

# Performance testing utilities
measure_execution_time() {
    local command="$1"
    local iterations="${2:-1}"
    local total_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start_time=$(date +%s%N)
        eval "$command" &>/dev/null
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
        total_time=$((total_time + duration))
    done
    
    local avg_time=$((total_time / iterations))
    echo "$avg_time"
}

assert_performance() {
    local command="$1"
    local max_time_ms="$2"
    local message="${3:-Command should complete within time limit}"
    
    local actual_time=$(measure_execution_time "$command")
    
    if [[ $actual_time -le $max_time_ms ]]; then
        test_pass "$message: ${actual_time}ms (limit: ${max_time_ms}ms)"
        return 0
    else
        test_fail "$message: ${actual_time}ms exceeded limit of ${max_time_ms}ms"
        return 1
    fi
}

# Test discovery and execution
discover_tests() {
    local test_dir="$1"
    find "$test_dir" -name "test-*.sh" -type f -executable
}

run_test_file() {
    local test_file="$1"
    
    echo -e "\n${BOLD}Running test file: $(basename "$test_file")${NC}"
    
    if bash "$test_file"; then
        return 0
    else
        return 1
    fi
}

run_all_tests() {
    local test_dir="${1:-$(dirname "${BASH_SOURCE[0]}")/../}"
    local failed_files=0
    
    while IFS= read -r test_file; do
        if ! run_test_file "$test_file"; then
            ((failed_files++))
        fi
    done < <(discover_tests "$test_dir")
    
    echo -e "\n${BOLD}=== Overall Test Summary ===${NC}"
    if [[ $failed_files -eq 0 ]]; then
        echo -e "${GREEN}All test files passed!${NC}"
        return 0
    else
        echo -e "${RED}$failed_files test file(s) failed!${NC}"
        return 1
    fi
}