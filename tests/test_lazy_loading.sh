#!/usr/bin/env bash
# ============================================================================
# Lazy Loading Test Suite
#
# Comprehensive testing for the enhanced lazy loading system including:
# - Context detection validation
# - Tool lazy loading verification
# - Performance regression testing
# - Integration testing
#
# Usage:
#   ./tests/test-lazy_loading.sh [--verbose] [--integration]
# ============================================================================

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZSH_CONFIG_DIR="$PROJECT_ROOT/dot_config/zsh"

# Test options
VERBOSE=false
RUN_INTEGRATION=false
TEST_RESULTS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging - match format with main test suite
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "  ${GREEN}✓${NC} $1"
    TEST_RESULTS+=("PASS: $1")
}

log_failure() {
    echo -e "  ${RED}✗${NC} $1"
    TEST_RESULTS+=("FAIL: $1")
    return 1
}

log_warning() {
    echo -e "  ${YELLOW}!${NC} $1"
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
Lazy Loading Test Suite

Usage: $0 [OPTIONS]

Options:
    --verbose, -v      Enable verbose output
    --integration, -i  Run integration tests
    --help, -h         Show this help

Test Categories:
    - Project context detection
    - Lazy loading wrapper validation
    - Performance characteristics
    - Tool availability testing
    - Integration testing (optional)
EOF
}

# Test: Project context detection
test_project_context_detection() {
    log_info "Testing project context detection..."
    
    # Create temporary test directories
    local temp_dir=$(mktemp -d)
    local original_pwd="$PWD"
    
    # Test Node.js project detection
    local nodejs_dir="$temp_dir/nodejs"
    mkdir -p "$nodejs_dir"
    cd "$nodejs_dir"
    echo '{"name":"test","version":"1.0.0"}' > package.json
    
    local context=$(zsh -c "
        source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'
        detect_project_context
    " 2>/dev/null)
    
    if [[ "$context" == *"nodejs"* ]]; then
        log_success "Node.js project detection"
    else
        log_failure "Node.js project detection (got: $context)"
    fi
    
    # Test Rust project detection
    local rust_dir="$temp_dir/rust"
    mkdir -p "$rust_dir"
    cd "$rust_dir"
    cat > Cargo.toml << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    
    context=$(zsh -c "
        source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'
        detect_project_context
    " 2>/dev/null)
    
    if [[ "$context" == *"rust"* ]]; then
        log_success "Rust project detection"
    else
        log_failure "Rust project detection (got: $context)"
    fi
    
    # Test Docker project detection
    local docker_dir="$temp_dir/docker"
    mkdir -p "$docker_dir"
    cd "$docker_dir"
    echo 'FROM ubuntu:20.04' > Dockerfile
    
    context=$(zsh -c "
        source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'
        detect_project_context
    " 2>/dev/null)
    
    if [[ "$context" == *"docker"* ]]; then
        log_success "Docker project detection"
    else
        log_failure "Docker project detection (got: $context)"
    fi
    
    # Test Kubernetes project detection
    local k8s_dir="$temp_dir/k8s"
    mkdir -p "$k8s_dir/k8s"
    cd "$k8s_dir"
    cat > k8s/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test
EOF
    
    context=$(zsh -c "
        source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'
        detect_project_context
    " 2>/dev/null)
    
    if [[ "$context" == *"k8s"* ]]; then
        log_success "Kubernetes project detection"
    else
        log_failure "Kubernetes project detection (got: $context)"
    fi
    
    # Test multiple contexts
    cd "$temp_dir"
    mkdir -p "multi"
    cd "multi"
    echo '{"name":"test"}' > package.json
    echo 'FROM node:16' > Dockerfile
    
    context=$(zsh -c "
        source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'
        detect_project_context
    " 2>/dev/null)
    
    if [[ "$context" == *"nodejs"* ]] && [[ "$context" == *"docker"* ]]; then
        log_success "Multiple context detection"
    else
        log_failure "Multiple context detection (got: $context)"
    fi
    
    # Cleanup
    cd "$original_pwd"
    rm -rf "$temp_dir"
}

# Test: Lazy loading wrapper functionality
test_lazy_loading_wrappers() {
    log_info "Testing lazy loading wrapper functionality..."
    
    # Test wrapper function creation
    local wrapper_test=$(zsh -c "
        # Set up test environment
        export LAZY_LOADING_ENABLED=1
        
        # Mock is_exist_command to simulate docker availability
        is_exist_command() {
            case \$1 in
                docker|docker-compose) return 0 ;;
                *) return 1 ;;
            esac
        }
        
        # Create simplified core functions that lazy_loading needs
        debug() { [[ -n \"\$DOTS_DEBUG\" ]] && echo \"[DEBUG] \$@\" >&2; }
        warn() { echo \"[WARN] \$@\" >&2; }
        
        # Source the lazy loading module
        source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'
        
        # Check if docker function is created (it should be auto-created)
        if (( \$+functions[docker] )); then
            echo 'WRAPPER_CREATED'
        else
            echo 'WRAPPER_MISSING'
        fi
    " 2>/dev/null)
    
    if [[ "$wrapper_test" == "WRAPPER_CREATED" ]]; then
        log_success "Lazy loading wrapper creation"
    else
        log_failure "Lazy loading wrapper creation"
    fi
    
    # Test is_project_context function
    local context_test=$(zsh -c "
        source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'
        PROJECT_CONTEXT='nodejs,docker'
        
        if is_project_context 'nodejs'; then
            echo 'NODEJS_DETECTED'
        else
            echo 'NODEJS_MISSING'
        fi
        
        if is_project_context 'rust'; then
            echo 'RUST_DETECTED'
        else
            echo 'RUST_MISSING'
        fi
    " 2>/dev/null)
    
    if [[ "$context_test" == *"NODEJS_DETECTED"* ]] && [[ "$context_test" == *"RUST_MISSING"* ]]; then
        log_success "Project context checking"
    else
        log_failure "Project context checking"
    fi
}

# Test: Performance characteristics
test_performance_characteristics() {
    log_info "Testing performance characteristics..."
    
    # Test startup time with lazy loading enabled vs disabled
    local with_lazy=$(bash -c "
        if command -v gdate >/dev/null 2>&1; then
            start=\$(gdate +%s%3N)
            LAZY_LOADING_ENABLED=1 zsh -c 'source \"$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh\"; exit 0' >/dev/null 2>&1
            end=\$(gdate +%s%3N)
        else
            start=\$(date +%s000)
            LAZY_LOADING_ENABLED=1 zsh -c 'source \"$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh\"; exit 0' >/dev/null 2>&1
            end=\$(date +%s000)
        fi
        echo \$((end - start))
    ")
    
    local without_lazy=$(bash -c "
        if command -v gdate >/dev/null 2>&1; then
            start=\$(gdate +%s%3N)
            LAZY_LOADING_ENABLED=0 zsh -c 'source \"$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh\"; exit 0' >/dev/null 2>&1
            end=\$(gdate +%s%3N)
        else
            start=\$(date +%s000)
            LAZY_LOADING_ENABLED=0 zsh -c 'source \"$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh\"; exit 0' >/dev/null 2>&1
            end=\$(date +%s000)
        fi
        echo \$((end - start))
    ")
    
    verbose "Startup time with lazy loading: ${with_lazy}ms"
    verbose "Startup time without lazy loading: ${without_lazy}ms"
    
    # Lazy loading should not significantly increase startup time
    if (( with_lazy <= without_lazy + 50 )); then
        log_success "Startup performance overhead acceptable (${with_lazy}ms vs ${without_lazy}ms)"
    else
        log_failure "Startup performance overhead too high (${with_lazy}ms vs ${without_lazy}ms)"
    fi
    
    # Test context detection performance
    local context_time=$(bash -c "
        temp_dir=\$(mktemp -d)
        cd \$temp_dir
        echo '{\"name\":\"test\"}' > package.json
        
        if command -v gdate >/dev/null 2>&1; then
            start=\$(gdate +%s%3N)
            for i in {1..10}; do
                zsh -c 'source \"$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh\"; detect_project_context' >/dev/null 2>&1
            done
            end=\$(gdate +%s%3N)
        else
            start=\$(date +%s000)
            for i in {1..10}; do
                zsh -c 'source \"$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh\"; detect_project_context' >/dev/null 2>&1
            done
            end=\$(date +%s000)
        fi
        
        rm -rf \$temp_dir
        echo \$((end - start))
    ")
    
    local avg_context_time=$((context_time / 10))
    verbose "Average context detection time: ${avg_context_time}ms"
    
    if (( avg_context_time <= 200 )); then
        log_success "Context detection performance acceptable (${avg_context_time}ms average)"
    else
        log_failure "Context detection performance too slow (${avg_context_time}ms average)"
    fi
}

# Test: Enhanced lazy tools functionality
test_enhanced_lazy_tools() {
    log_info "Testing enhanced lazy tools functionality..."
    
    # Test enhanced mise detection
    local mise_test=$(zsh -c "
        source '$ZSH_CONFIG_DIR/modules/tools/enhanced_lazy_tools.zsh'
        
        # Test function existence
        if (( \$+functions[_enhanced_mise_init] )); then
            echo 'MISE_FUNCTION_EXISTS'
        fi
        
        if (( \$+functions[_enhanced_atuin_init] )); then
            echo 'ATUIN_FUNCTION_EXISTS'  
        fi
        
        if (( \$+functions[_enhanced_starship_init] )); then
            echo 'STARSHIP_FUNCTION_EXISTS'
        fi
    " 2>/dev/null)
    
    if [[ "$mise_test" == *"MISE_FUNCTION_EXISTS"* ]] && 
       [[ "$mise_test" == *"ATUIN_FUNCTION_EXISTS"* ]] && 
       [[ "$mise_test" == *"STARSHIP_FUNCTION_EXISTS"* ]]; then
        log_success "Enhanced lazy tools function availability"
    else
        log_failure "Enhanced lazy tools function availability"
    fi
    
    # Test tool usage tracking (if enabled)
    local tracking_test=$(zsh -c "
        source '$ZSH_CONFIG_DIR/modules/tools/enhanced_lazy_tools.zsh'
        
        if (( \$+functions[_track_tool_usage] )); then
            echo 'TRACKING_AVAILABLE'
        fi
        
        if (( \$+functions[get_tool_usage_stats] )); then
            echo 'STATS_AVAILABLE'
        fi
    " 2>/dev/null)
    
    if [[ "$tracking_test" == *"TRACKING_AVAILABLE"* ]] && [[ "$tracking_test" == *"STATS_AVAILABLE"* ]]; then
        log_success "Tool usage tracking functionality"
    else
        log_failure "Tool usage tracking functionality"
    fi
}

# Test: Module integration
test_module_integration() {
    log_info "Testing module integration..."
    
    # Test that modules can be loaded together
    local integration_test=$(zsh -c "
        export LAZY_LOADING_ENABLED=1
        
        # Mock required functions to avoid dependency issues
        declare_module() { : ; }
        debug() { [[ -n \"\$DOTS_DEBUG\" ]] && echo \"[DEBUG] \$@\" >&2; }
        warn() { echo \"[WARN] \$@\" >&2; }
        is_exist_command() { return 1; }  # Mock no tools available
        
        # Load lazy loading modules
        source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'
        source '$ZSH_CONFIG_DIR/modules/tools/enhanced_lazy_tools.zsh'
        
        # Test basic functionality
        local functions_available=0
        
        if (( \$+functions[detect_project_context] )); then
            ((functions_available++))
        fi
        
        if (( \$+functions[is_project_context] )); then
            ((functions_available++))
        fi
        
        if (( \$+functions[_enhanced_mise_init] )); then
            ((functions_available++))
        fi
        
        # At least 2 of the 3 functions should be available
        if (( functions_available >= 2 )); then
            echo 'INTEGRATION_SUCCESS'
        else
            echo 'INTEGRATION_FAILURE'
        fi
    " 2>/dev/null)
    
    if [[ "$integration_test" == "INTEGRATION_SUCCESS" ]]; then
        log_success "Module integration"
    else
        log_failure "Module integration"
    fi
}

# Test: Integration with real tools (if available)
test_real_tool_integration() {
    [[ "$RUN_INTEGRATION" == "false" ]] && return 0
    
    log_info "Testing integration with real tools..."
    
    # Test with actual tools if available
    local tools=(docker kubectl npm yarn)
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            verbose "Testing real $tool integration..."
            
            local tool_test=$(zsh -c "
                # Set up a signal handler for timeout
                TMOUT=30

                source '$ZSH_CONFIG_DIR/modules/tools/lazy_loading.zsh'

                # Test lazy loading wrapper
                if (( \$+functions[$tool] )); then
                    # Try to execute help (should initialize)
                    $tool --help >/dev/null 2>&1 || true
                    echo 'TOOL_EXECUTED'
                else
                    echo 'TOOL_NOT_WRAPPED'
                fi
            " 2>/dev/null || echo "TIMEOUT")
            
            if [[ "$tool_test" == "TOOL_EXECUTED" ]]; then
                log_success "Real $tool integration"
            elif [[ "$tool_test" == "TOOL_NOT_WRAPPED" ]]; then
                log_warning "$tool not wrapped (tool not available or lazy loading disabled)"
            else
                log_failure "Real $tool integration (timeout or error)"
            fi
        else
            verbose "$tool not available for testing"
        fi
    done
}

# Generate test report
generate_report() {
    echo
    log_info "Test Summary"
    echo "============="
    
    local passed=0
    local failed=0
    
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == PASS:* ]]; then
            echo -e "  ${GREEN}✓${NC} ${result#PASS: }"
            ((passed++))
        else
            echo -e "  ${RED}✗${NC} ${result#FAIL: }"
            ((failed++))
        fi
    done
    
    echo
    echo -e "${BLUE}Results:${NC} $passed passed, $failed failed"
    
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓ All lazy loading tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some lazy loading tests failed!${NC}"
        return 1
    fi
}

# Main test runner
run_tests() {
    log_info "Starting lazy loading test suite..."
    echo
    
    # Check environment
    if [[ ! -d "$ZSH_CONFIG_DIR" ]]; then
        log_failure "Zsh configuration directory not found: $ZSH_CONFIG_DIR"
        exit 1
    fi
    
    # Run test categories
    local test_functions=(
        test_project_context_detection
        test_lazy_loading_wrappers
        test_enhanced_lazy_tools
        test_performance_characteristics
        test_module_integration
        test_real_tool_integration
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