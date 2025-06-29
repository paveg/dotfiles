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

# Initialize results
echo '{"benchmarks": []}' > "$RESULTS_FILE"

# Helper functions
get_time_ms() {
    if [[ "$(uname)" == "Darwin" ]]; then
        python3 -c "import time; print(int(time.time() * 1000))"
    else
        echo $(( $(date +%s%N) / 1000000 ))
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
    
    local start_time=$(get_time_ms)
    
    # Test completion loading by triggering compinit
    if zsh -c 'autoload -U compinit; compinit -d ~/.zcompdump-test; rm -f ~/.zcompdump-test*' &>/dev/null; then
        local end_time=$(get_time_ms)
        local duration=$((end_time - start_time))
        
        success "Completion system loaded in ${duration}ms"
        add_result "completion_loading" "$duration" "$duration" "$duration" true
        return 0
    else
        error "Completion system loading failed"
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

# Main benchmarking function
main() {
    echo "🚀 Starting Dotfiles Performance Benchmark"
    echo "=========================================="
    
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