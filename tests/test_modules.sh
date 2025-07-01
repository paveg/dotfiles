#!/usr/bin/env bash
# ============================================================================
# Module System Test Suite
#
# Comprehensive testing for the enhanced module system including:
# - Module metadata validation
# - Dependency resolution testing
# - Loading order verification
# - Performance benchmarking
# - Integration testing
#
# Usage:
#   ./tests/test-modules.sh [--verbose] [--benchmark] [--integration]
# ============================================================================

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZSH_DIR="$PROJECT_ROOT/dot_config/zsh"
MODULES_DIR="$ZSH_DIR/modules"

# Test options
VERBOSE=false
RUN_BENCHMARK=false
RUN_INTEGRATION=false
TEST_RESULTS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TEST_RESULTS+=("PASS: $1")
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    TEST_RESULTS+=("FAIL: $1")
    return 1
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

verbose() {
    [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[VERBOSE]${NC} $1"
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --benchmark|-b)
                RUN_BENCHMARK=true
                shift
                ;;
            --integration|-i)
                RUN_INTEGRATION=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Module System Test Suite

Usage: $0 [OPTIONS]

Options:
    --verbose, -v      Enable verbose output
    --benchmark, -b    Run performance benchmarks
    --integration, -i  Run integration tests
    --help, -h         Show this help

Test Categories:
    - Basic structure validation
    - Module metadata validation  
    - Dependency resolution testing
    - Loading order verification
    - Function availability testing
    - Performance benchmarking (optional)
    - Integration testing (optional)
EOF
}

# Test: Basic structure validation
test_structure() {
    log_info "Testing basic module structure..."
    
    # Check if modules directory exists
    if [[ ! -d "$MODULES_DIR" ]]; then
        log_failure "Modules directory not found: $MODULES_DIR"
        return 1
    fi
    
    # Check if init.zsh exists
    if [[ ! -f "$ZSH_DIR/init.zsh" ]]; then
        log_failure "init.zsh not found: $ZSH_DIR/init.zsh"
        return 1
    fi
    
    # Check categorized structure
    local categories=("core" "config" "tools" "ui" "utils" "experimental" "local")
    for category in "${categories[@]}"; do
        if [[ ! -d "$MODULES_DIR/$category" ]]; then
            log_failure "Category directory missing: $category"
            return 1
        fi
        verbose "Found category directory: $category"
    done
    
    # Check core modules exist
    local core_modules=("platform.zsh" "core.zsh" "metadata.zsh" "loader.zsh")
    for module in "${core_modules[@]}"; do
        if [[ ! -f "$MODULES_DIR/core/$module" ]]; then
            log_failure "Core module missing: $module"
            return 1
        fi
        verbose "Found core module: $module"
    done
    
    log_success "Basic structure validation"
}

# Test: Module metadata validation
test_metadata() {
    log_info "Testing module metadata..."
    
    local errors=0
    
    # Find all module files
    while IFS= read -r -d '' module_file; do
        local module_name="$(basename "$module_file" .zsh)"
        verbose "Checking metadata for: $module_name"
        
        # Check if module has metadata declaration
        if ! grep -q "declare_module" "$module_file"; then
            log_warning "Module missing metadata: $module_name"
            ((errors++))
            continue
        fi
        
        # Validate metadata format
        local metadata_section=$(sed -n '/declare_module/,/^[[:space:]]*$/p' "$module_file")
        
        # Check for required fields
        if ! echo "$metadata_section" | grep -q "category:"; then
            log_warning "Module missing category: $module_name"
            ((errors++))
        fi
        
        if ! echo "$metadata_section" | grep -q "description:"; then
            log_warning "Module missing description: $module_name"
            ((errors++))
        fi
        
        verbose "Metadata validated for: $module_name"
        
    done < <(find "$MODULES_DIR" -name "*.zsh" -type f -print0)
    
    if [[ $errors -eq 0 ]]; then
        log_success "Module metadata validation"
    else
        log_failure "Module metadata validation ($errors issues found)"
        return 1
    fi
}

# Test: Dependency resolution
test_dependencies() {
    log_info "Testing dependency resolution..."
    
    # Create a test script that loads the module system
    local test_script="$MODULES_DIR/test_deps.zsh"
    
    cat > "$test_script" << EOF
#!/usr/bin/env zsh
setopt NO_GLOBAL_RCS  # Prevent loading system zsh configs
export XDG_CONFIG_HOME="$PROJECT_ROOT"
export ZDOTDIR="\$XDG_CONFIG_HOME/dot_config/zsh"
export DOTS_DEBUG=0

# Source the metadata system
source "\$ZDOTDIR/modules/core/metadata.zsh"

# Test circular dependency detection
declare_module "test_a" "depends:test_b"
declare_module "test_b" "depends:test_c" 
declare_module "test_c" "depends:test_a"

# This should fail with circular dependency
if get_load_order >/dev/null 2>&1; then
    echo "FAIL: Circular dependency not detected"
    exit 1
else
    echo "PASS: Circular dependency correctly detected"
fi

# Test valid dependency resolution
unset MODULE_METADATA
source "$ZDOTDIR/modules/core/metadata.zsh"

declare_module "test_base" "category:test"
declare_module "test_mid" "depends:test_base" "category:test"
declare_module "test_top" "depends:test_mid" "category:test"

local load_order=($(get_load_order))
if [[ "${load_order[1]}" == "test_base" ]] && [[ "${load_order[2]}" == "test_mid" ]] && [[ "${load_order[3]}" == "test_top" ]]; then
    echo "PASS: Dependency resolution works correctly"
else
    echo "FAIL: Dependency resolution incorrect: ${load_order[*]}"
    exit 1
fi
EOF
    
    # Run the test
    if zsh "$test_script" >/dev/null 2>&1; then
        log_success "Dependency resolution testing"
    else
        log_failure "Dependency resolution testing"
        return 1
    fi
    
    # Cleanup
    rm -f "$test_script"
}

# Test: Module loading
test_loading() {
    log_info "Testing module loading..."
    
    # Create test script for loading
    local test_script="$MODULES_DIR/test_loading.zsh"
    
    cat > "$test_script" << EOF
#!/usr/bin/env zsh
setopt NO_GLOBAL_RCS
export XDG_CONFIG_HOME="$PROJECT_ROOT"
export ZDOTDIR="\$XDG_CONFIG_HOME/dot_config/zsh"
export DOTS_DEBUG=0
export DOTS_ONLY_MODULES="platform,core"

# Test minimal loading
source "\$ZDOTDIR/init.zsh"

# Check if core functions are available
if ! (( $+functions[is_exist_command] )); then
    echo "FAIL: is_exist_command not available"
    exit 1
fi

if ! (( $+functions[zcompare] )); then
    echo "FAIL: zcompare not available"
    exit 1
fi

echo "PASS: Core functions loaded correctly"
EOF
    
    if zsh "$test_script" >/dev/null 2>&1; then
        log_success "Module loading testing"
    else
        log_failure "Module loading testing"
        return 1
    fi
    
    rm -f "$test_script"
}

# Test: Performance benchmarking
test_performance() {
    [[ "$RUN_BENCHMARK" == "false" ]] && return 0
    
    log_info "Running performance benchmarks..."
    
    # Test startup time
    local startup_times=()
    for i in {1..5}; do
        local start_time=$(date +%s%3N)
        
        # Run a minimal shell that loads the module system
        zsh -c "
            export XDG_CONFIG_HOME='${XDG_CONFIG_HOME:-$HOME/.config}'
            export ZDOTDIR='$XDG_CONFIG_HOME/zsh'
            export DOTS_DEBUG=0
            source '$ZSH_DIR/init.zsh'
            exit 0
        " >/dev/null 2>&1
        
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        startup_times+=($duration)
        
        verbose "Startup attempt $i: ${duration}ms"
    done
    
    # Calculate average
    local total=0
    for time in "${startup_times[@]}"; do
        ((total += time))
    done
    local average=$((total / ${#startup_times[@]}))
    
    log_info "Average startup time: ${average}ms"
    
    # Performance thresholds
    if [[ $average -lt 200 ]]; then
        log_success "Performance benchmark (${average}ms - excellent)"
    elif [[ $average -lt 500 ]]; then
        log_success "Performance benchmark (${average}ms - good)"
    elif [[ $average -lt 1000 ]]; then
        log_warning "Performance benchmark (${average}ms - acceptable)"
    else
        log_failure "Performance benchmark (${average}ms - needs optimization)"
        return 1
    fi
}

# Test: Integration testing
test_integration() {
    [[ "$RUN_INTEGRATION" == "false" ]] && return 0
    
    log_info "Running integration tests..."
    
    # Test full system loading
    local test_script="$MODULES_DIR/test_integration.zsh"
    
    cat > "$test_script" << EOF
#!/usr/bin/env zsh
setopt NO_GLOBAL_RCS
export XDG_CONFIG_HOME="$PROJECT_ROOT"
export ZDOTDIR="\$XDG_CONFIG_HOME/dot_config/zsh"
export DOTS_DEBUG=0

# Load full system
source "\$ZDOTDIR/init.zsh"

# Test that key functions are available
local required_functions=(
    "is_exist_command"
    "zcompare"
    "load_module"
    "list_modules"
    "show_module_info"
)

for func in "${required_functions[@]}"; do
    if ! (( $+functions[$func] )); then
        echo "FAIL: Required function not available: $func"
        exit 1
    fi
done

# Test module management commands
if ! list_modules >/dev/null 2>&1; then
    echo "FAIL: list_modules command failed"
    exit 1
fi

if ! validate_modules >/dev/null 2>&1; then
    echo "FAIL: validate_modules command failed"
    exit 1
fi

echo "PASS: Integration tests completed"
EOF
    
    if zsh "$test_script" >/dev/null 2>&1; then
        log_success "Integration testing"
    else
        log_failure "Integration testing"
        return 1
    fi
    
    rm -f "$test_script"
}

# Test: Syntax validation
test_syntax() {
    log_info "Testing zsh syntax validation..."
    
    local errors=0
    
    # Check syntax of all module files
    while IFS= read -r -d '' module_file; do
        local module_name="$(basename "$module_file" .zsh)"
        verbose "Checking syntax: $module_name"
        
        if ! zsh -n "$module_file" 2>/dev/null; then
            log_failure "Syntax error in: $module_name"
            ((errors++))
        fi
    done < <(find "$MODULES_DIR" -name "*.zsh" -type f -print0)
    
    # Check init.zsh syntax
    if ! zsh -n "$ZSH_DIR/init.zsh" 2>/dev/null; then
        log_failure "Syntax error in: init.zsh"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Syntax validation"
    else
        log_failure "Syntax validation ($errors files with errors)"
        return 1
    fi
}

# Generate test report
generate_report() {
    log_info "Test Summary"
    echo "============="
    
    local passed=0
    local failed=0
    
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
        if [[ "$result" == PASS:* ]]; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    echo
    echo "Results: $passed passed, $failed failed"
    
    if [[ $failed -eq 0 ]]; then
        log_success "All tests passed!"
        return 0
    else
        log_failure "Some tests failed!"
        return 1
    fi
}

# Main test runner
run_tests() {
    log_info "Starting module system test suite..."
    echo
    
    # Check environment
    if [[ ! -d "$ZSH_DIR" ]]; then
        log_failure "Zsh configuration directory not found: $ZSH_DIR"
        exit 1
    fi
    
    # Run test categories
    local test_functions=(
        test_structure
        test_syntax
        test_metadata
        test_dependencies
        test_loading
        test_performance
        test_integration
    )
    
    for test_func in "${test_functions[@]}"; do
        echo
        if ! $test_func; then
            # Test failed, but continue with other tests
            :
        fi
    done
    
    echo
    generate_report
}

# Main execution
main() {
    parse_args "$@"
    run_tests
}

main "$@"