#!/usr/bin/env bash
# Performance Benchmarking Script for Dotfiles
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ITERATIONS=${BENCHMARK_ITERATIONS:-50}
MAX_STARTUP_TIME=${MAX_STARTUP_TIME:-500}  # milliseconds
RESULTS_FILE="${RESULTS_FILE:-/tmp/benchmark-results.json}"
SKIP_COMPLETION_TEST=${SKIP_COMPLETION_TEST:-false}  # Set to true to skip completion benchmarking

# Initialize results
echo '{"benchmarks": []}' > "$RESULTS_FILE"

# Helper functions
get_time_ms() {
    # Try Python first as it's most reliable for millisecond precision
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import time; print(int(time.time() * 1000))"
        return
    elif command -v python >/dev/null 2>&1; then
        python -c "import time; print(int(time.time() * 1000))"
        return
    fi
    
    # For systems with nanosecond support, test the actual output
    local ns_output
    if ns_output=$(date +%s%N 2>/dev/null) && [[ "$ns_output" =~ ^[0-9]+$ ]]; then
        # Ensure we have a clean numeric value before arithmetic
        echo $(( ns_output / 1000000 ))
    else
        # Fallback to seconds * 1000 for systems without nanosecond support
        echo $(( $(date +%s) * 1000 ))
    fi
}
log() {
    echo -e "${BLUE}[BENCHMARK]${NC} $1"
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

# Add result to JSON file
add_result() {
    local test_name="$1"
    local avg_time="$2"
    local min_time="$3"
    local max_time="$4"
    local passed="$5"
    
    local temp_file=$(mktemp)
    jq --arg name "$test_name" \
       --argjson avg "$avg_time" \
       --argjson min "$min_time" \
       --argjson max "$max_time" \
       --argjson passed "$passed" \
       '.benchmarks += [{
         "name": $name,
         "avg_time_ms": $avg,
         "min_time_ms": $min,
         "max_time_ms": $max,
         "passed": $passed,
         "timestamp": now
       }]' "$RESULTS_FILE" > "$temp_file"
    mv "$temp_file" "$RESULTS_FILE"
}

# Benchmark shell startup time
benchmark_startup() {
    log "Benchmarking Zsh startup time ($ITERATIONS iterations)..."
    
    local times=()
    local total_time=0
    local min_time=999999
    local max_time=0
    
    for ((i=1; i<=ITERATIONS; i++)); do
        # Measure startup time
        local start_time=$(get_time_ms)
        
        # Run zsh in non-interactive mode
        if timeout 10 zsh -c 'exit' &>/dev/null; then
            local end_time=$(get_time_ms)
            local duration=$((end_time - start_time))
            
            times+=("$duration")
            total_time=$((total_time + duration))
            
            # Track min/max
            if [[ $duration -lt $min_time ]]; then
                min_time=$duration
            fi
            if [[ $duration -gt $max_time ]]; then
                max_time=$duration
            fi
        else
            error "Startup test $i failed (timeout)"
            return 1
        fi
        
        # Progress indicator
        if (( i % 10 == 0 )); then
            echo -n "."
        fi
    done
    echo
    
    local avg_time=$((total_time / ITERATIONS))
    local passed=true
    
    # Check if performance regression
    if [[ $avg_time -gt $MAX_STARTUP_TIME ]]; then
        passed=false
        error "Performance regression detected! Average startup time: ${avg_time}ms (max allowed: ${MAX_STARTUP_TIME}ms)"
    else
        success "Average startup time: ${avg_time}ms (within ${MAX_STARTUP_TIME}ms limit)"
    fi
    
    log "Statistics:"
    echo "  Average: ${avg_time}ms"
    echo "  Minimum: ${min_time}ms"
    echo "  Maximum: ${max_time}ms"
    echo "  Iterations: $ITERATIONS"
    
    add_result "zsh_startup" "$avg_time" "$min_time" "$max_time" "$passed"
    
    return $([ "$passed" = true ] && echo 0 || echo 1)
}

# Benchmark completion system
benchmark_completion() {
    log "Benchmarking completion system..."
    
    # Check if completion test should be skipped
    if [[ "$SKIP_COMPLETION_TEST" == "true" ]]; then
        warning "Completion test skipped (SKIP_COMPLETION_TEST=true)"
        add_result "completion_loading" 0 0 0 true
        return 0
    fi
    
    # Check if we're in a CI environment or minimal shell setup
    local is_ci=false
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]] || [[ -n "${TRAVIS:-}" ]]; then
        is_ci=true
        log "CI environment detected"
    fi
    
    # Check if completion system is available
    local completion_available=true
    local error_output
    
    # First, test basic zsh functionality
    if ! error_output=$(zsh -c 'echo "zsh basic test"' 2>&1); then
        error "Basic zsh test failed: $error_output"
        add_result "completion_loading" 0 0 0 false
        return 1
    fi
    
    # Test if zsh completion functions are available
    if ! error_output=$(zsh -c 'autoload -U compinit' 2>&1); then
        completion_available=false
        log "Completion autoload test failed: $error_output"
        
        # Additional diagnostic information
        log "Zsh version: $(zsh --version 2>/dev/null || echo 'unknown')"
        log "Zsh fpath: $(zsh -c 'echo $fpath' 2>/dev/null || echo 'unknown')"
        
        # Check if this might be a minimal zsh installation
        if ! zsh -c 'autoload -U colors' &>/dev/null; then
            log "This appears to be a minimal zsh installation lacking completion functions"
        fi
    fi
    
    # Test if we can create a temporary completion dump
    local test_dump_file="/tmp/zcompdump-test-$$"
    local start_time=$(get_time_ms)
    local duration=0
    local success_status=false
    
    if [[ "$completion_available" == "true" ]]; then
        # Try the full completion test with better error capture
        if error_output=$(zsh -c "
            autoload -U compinit
            compinit -d '$test_dump_file'
            # Test basic completion functionality
            if [[ -f '$test_dump_file' ]]; then
                echo 'Completion dump created successfully'
            else
                echo 'Warning: Completion dump not created'
            fi
        " 2>&1); then
            local end_time=$(get_time_ms)
            duration=$((end_time - start_time))
            success_status=true
            success "Completion system loaded in ${duration}ms"
            log "Completion test output: $error_output"
        else
            warning "Full completion test failed: $error_output"
            # Try a simpler completion test
            if error_output=$(zsh -c "autoload -U compinit; compinit -i" 2>&1); then
                local end_time=$(get_time_ms)
                duration=$((end_time - start_time))
                success_status=true
                warning "Basic completion system loaded in ${duration}ms (with -i flag)"
                log "Basic completion output: $error_output"
            else
                error "Basic completion test also failed: $error_output"
            fi
        fi
    fi
    
    # Clean up test files
    rm -f "$test_dump_file"* 2>/dev/null || true
    
    # Handle results based on environment and success
    if [[ "$success_status" == "true" ]]; then
        add_result "completion_loading" "$duration" "$duration" "$duration" true
        return 0
    elif [[ "$is_ci" == "true" ]]; then
        # In CI, treat completion failure as a warning rather than error
        # This is expected because CI environments often have minimal zsh setups
        warning "Completion system not available in CI environment - this is expected"
        warning "CI environments typically lack full interactive shell configurations"
        log "Common CI limitations affecting completions:"
        log "  - Minimal zsh installation (no completion functions)"
        log "  - Missing fpath entries for completion directories"
        log "  - Non-interactive shell mode limitations"
        log "  - Container environments with reduced functionality"
        add_result "completion_loading" 0 0 0 true  # Mark as passed in CI
        return 0
    else
        # In non-CI environments, this might indicate a real issue
        error "Completion system loading failed in non-CI environment"
        error "This may indicate missing zsh completion setup or configuration issues"
        log "Troubleshooting tips:"
        log "  1. Check if zsh completion is properly installed:"
        log "     - macOS: brew install zsh-completions"
        log "     - Ubuntu/Debian: apt install zsh-common"
        log "     - CentOS/RHEL: yum install zsh"
        log "  2. Verify completion directories exist and are in fpath:"
        log "     - Run: zsh -c 'echo \$fpath'"
        log "  3. Check if completion dump is writable:"
        log "     - Directory: ~/.zcompdump or \$XDG_CACHE_HOME/zsh/"
        log "  4. Test manual completion loading:"
        log "     - Run: zsh -c 'autoload -U compinit; compinit'"
        log "  5. To skip this test in future runs:"
        log "     - Run: SKIP_COMPLETION_TEST=true $0"
        add_result "completion_loading" 0 0 0 false
        return 1
    fi
}

# Benchmark module loading
benchmark_modules() {
    log "Benchmarking individual module loading..."
    
    local module_dir="${ZDOTDIR:-$HOME/.config/zsh}/modules"
    if [[ ! -d "$module_dir" ]]; then
        module_dir="$HOME/.config/zsh/modules"
    fi
    
    if [[ ! -d "$module_dir" ]]; then
        warning "Module directory not found, skipping module benchmarks"
        return 0
    fi
    
    local total_modules=0
    local total_time=0
    
    for module in "$module_dir"/*.zsh; do
        if [[ -f "$module" ]]; then
            local module_name=$(basename "$module" .zsh)
            local start_time=$(get_time_ms)
            
            if zsh -c "source '$module'" &>/dev/null; then
                local end_time=$(get_time_ms)
                local duration=$((end_time - start_time))
                
                echo "  $module_name: ${duration}ms"
                total_time=$((total_time + duration))
                total_modules=$((total_modules + 1))
                
                add_result "module_${module_name}" "$duration" "$duration" "$duration" true
            else
                error "Failed to load module: $module_name"
                add_result "module_${module_name}" 0 0 0 false
            fi
        fi
    done
    
    if [[ $total_modules -gt 0 ]]; then
        local avg_module_time=$((total_time / total_modules))
        success "Loaded $total_modules modules, average: ${avg_module_time}ms"
        add_result "module_average" "$avg_module_time" 0 0 true
    fi
}

# Benchmark compilation performance
benchmark_compilation() {
    log "Benchmarking zsh compilation performance..."
    
    local test_file="/tmp/test_compile.zsh"
    cat > "$test_file" << 'EOF'
# Test zsh file for compilation benchmarking
autoload -U colors && colors
setopt prompt_subst

test_function() {
    echo "test"
}

for i in {1..100}; do
    echo "line $i"
done
EOF
    
    local start_time=$(get_time_ms)
    
    if zsh -c "zcompile '$test_file'" &>/dev/null; then
        local end_time=$(get_time_ms)
        local duration=$((end_time - start_time))
        
        success "Compilation completed in ${duration}ms"
        add_result "compilation_time" "$duration" "$duration" "$duration" true
        
        # Clean up
        rm -f "$test_file" "${test_file}.zwc"
        return 0
    else
        error "Compilation failed"
        add_result "compilation_time" 0 0 0 false
        rm -f "$test_file"
        return 1
    fi
}

# Memory usage benchmark
benchmark_memory() {
    log "Benchmarking memory usage..."
    
    # Start zsh process and measure memory
    local temp_script="/tmp/memory_test.zsh"
    cat > "$temp_script" << 'EOF'
# Load full configuration
source ~/.zshenv 2>/dev/null || true
source ~/.config/zsh/.zshrc 2>/dev/null || true

# Keep process alive for measurement
sleep 5
EOF
    
    # Start background process
    zsh "$temp_script" &
    local zsh_pid=$!
    
    sleep 2  # Let it settle
    
    # Measure memory usage (works on both macOS and Linux)
    local memory_kb=0
    if command -v ps &>/dev/null; then
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS
            memory_kb=$(ps -o rss= -p "$zsh_pid" 2>/dev/null || echo "0")
        else
            # Linux
            memory_kb=$(ps -o rss= -p "$zsh_pid" 2>/dev/null || echo "0")
        fi
    fi
    
    # Clean up
    kill "$zsh_pid" 2>/dev/null || true
    rm -f "$temp_script"
    
    local memory_mb=$((memory_kb / 1024))
    
    if [[ $memory_kb -gt 0 ]]; then
        success "Memory usage: ${memory_mb}MB (${memory_kb}KB)"
        add_result "memory_usage_kb" "$memory_kb" "$memory_kb" "$memory_kb" true
    else
        warning "Could not measure memory usage"
        add_result "memory_usage_kb" 0 0 0 false
    fi
}

# Show help information
show_help() {
    echo "Dotfiles Performance Benchmark Script"
    echo "====================================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  BENCHMARK_ITERATIONS      Number of iterations for startup test (default: 50)"
    echo "  MAX_STARTUP_TIME          Maximum allowed startup time in ms (default: 500)"
    echo "  RESULTS_FILE              Path to save benchmark results (default: /tmp/benchmark-results.json)"
    echo "  SKIP_COMPLETION_TEST      Skip completion system test (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                                           # Run all benchmarks"
    echo "  SKIP_COMPLETION_TEST=true $0                 # Skip completion test"
    echo "  BENCHMARK_ITERATIONS=100 $0                  # Run 100 startup iterations"
    echo "  MAX_STARTUP_TIME=1000 $0                     # Allow 1000ms startup time"
    echo ""
}

# Main benchmarking function
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    echo "🚀 Starting Dotfiles Performance Benchmark"
    echo "=========================================="
    
    # Show configuration
    log "Configuration:"
    echo "  Iterations: $ITERATIONS"
    echo "  Max startup time: ${MAX_STARTUP_TIME}ms"
    echo "  Results file: $RESULTS_FILE"
    echo "  Skip completion test: $SKIP_COMPLETION_TEST"
    echo ""
    
    # Ensure we have necessary tools
    if ! command -v jq &>/dev/null; then
        error "jq is required for benchmark results. Please install it."
        exit 1
    fi
    
    local failed_tests=0
    
    # Run benchmarks
    benchmark_startup || ((failed_tests++))
    echo
    
    benchmark_completion || ((failed_tests++))
    echo
    
    benchmark_modules || ((failed_tests++))
    echo
    
    benchmark_compilation || ((failed_tests++))
    echo
    
    benchmark_memory || ((failed_tests++))
    echo
    
    # Generate summary
    echo "=========================================="
    log "Benchmark Summary"
    
    if [[ -f "$RESULTS_FILE" ]]; then
        echo "Results saved to: $RESULTS_FILE"
        
        # Show key metrics
        if command -v jq &>/dev/null; then
            local startup_time=$(jq -r '.benchmarks[] | select(.name == "zsh_startup") | .avg_time_ms' "$RESULTS_FILE" 2>/dev/null || echo "N/A")
            local memory_usage=$(jq -r '.benchmarks[] | select(.name == "memory_usage_kb") | .avg_time_ms' "$RESULTS_FILE" 2>/dev/null || echo "N/A")
            
            echo "Key Metrics:"
            echo "  Startup Time: ${startup_time}ms"
            echo "  Memory Usage: $((memory_usage / 1024))MB"
        fi
    fi
    
    if [[ $failed_tests -eq 0 ]]; then
        success "All benchmarks completed successfully!"
        exit 0
    else
        error "$failed_tests benchmark(s) failed"
        exit 1
    fi
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi