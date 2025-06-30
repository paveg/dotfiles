#!/usr/bin/env bash
# ============================================================================
# Zsh Startup Performance Benchmarking Script
#
# This script provides comprehensive benchmarking for zsh startup performance
# with different configurations and lazy loading scenarios.
#
# Usage:
#   ./scripts/benchmark-startup.sh [--iterations N] [--profile] [--compare]
# ============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ITERATIONS="${BENCHMARK_ITERATIONS:-10}"
PROFILE_MODE=false
COMPARE_MODE=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --iterations|-i)
            ITERATIONS="$2"
            shift 2
            ;;
        --profile|-p)
            PROFILE_MODE=true
            shift
            ;;
        --compare|-c)
            COMPARE_MODE=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
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

show_help() {
    cat << EOF
Zsh Startup Performance Benchmarking

Usage: $0 [OPTIONS]

Options:
    --iterations, -i N    Number of iterations per test (default: $ITERATIONS)
    --profile, -p         Enable detailed profiling with zprofiler
    --compare, -c         Compare different loading strategies
    --verbose, -v         Enable verbose output
    --help, -h            Show this help

Examples:
    $0                    # Basic benchmark with default iterations
    $0 -i 20 -p          # 20 iterations with profiling
    $0 -c                # Compare different strategies
    $0 -v -p             # Verbose profiling mode

Environment Variables:
    BENCHMARK_ITERATIONS  Default number of iterations
    DOTS_DEBUG           Enable debug output during benchmarks
    
EOF
}

# Logging functions
log() {
    echo -e "${BLUE}[BENCH]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_result() {
    local time=$1
    local description=$2
    local color=""
    
    # Color code based on performance thresholds
    if (( $(echo "$time < 100" | bc -l) )); then
        color="$GREEN"  # Excellent < 100ms
    elif (( $(echo "$time < 300" | bc -l) )); then
        color="$BLUE"   # Good < 300ms
    elif (( $(echo "$time < 500" | bc -l) )); then
        color="$YELLOW" # Acceptable < 500ms
    else
        color="$RED"    # Needs optimization >= 500ms
    fi
    
    printf "${color}%8.1fms${NC} %s\n" "$time" "$description"
}

# Benchmark a specific zsh configuration
benchmark_config() {
    local config_name="$1"
    local config_setup="$2"
    local times=()
    
    log "Benchmarking: $config_name"
    
    for ((i=1; i<=ITERATIONS; i++)); do
        [[ "$VERBOSE" == "true" ]] && echo -n "  Run $i/$ITERATIONS..."
        
        # Run zsh with the specific configuration and measure time
        local start_time=$(date +%s%3N)
        
        # Execute the test configuration
        eval "$config_setup" >/dev/null 2>&1
        
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        times+=($duration)
        
        [[ "$VERBOSE" == "true" ]] && echo " ${duration}ms"
    done
    
    # Calculate statistics
    local total=0
    local min=${times[0]}
    local max=${times[0]}
    
    for time in "${times[@]}"; do
        total=$((total + time))
        (( time < min )) && min=$time
        (( time > max )) && max=$time
    done
    
    local avg=$((total / ITERATIONS))
    
    # Calculate median
    local sorted=($(printf '%s\n' "${times[@]}" | sort -n))
    local median_idx=$((ITERATIONS / 2))
    local median=${sorted[$median_idx]}
    
    # Store results
    printf "%-25s avg:%6.1fms  median:%6.1fms  min:%6.1fms  max:%6.1fms\n" \
        "$config_name" "$avg" "$median" "$min" "$max"
    
    return $avg
}

# Test basic shell startup
test_basic_startup() {
    log "Testing basic shell startup performance"
    echo
    
    # Test minimal zsh (no config)
    benchmark_config "Minimal zsh" \
        "zsh -c 'exit 0'"
    
    # Test with config but no modules
    benchmark_config "Config only" \
        "DOTS_SKIP_MODULES='*' zsh -l -c 'exit 0'"
    
    # Test core modules only
    benchmark_config "Core modules only" \
        "DOTS_ONLY_MODULES='platform,core,config' zsh -l -c 'exit 0'"
    
    # Test without plugins
    benchmark_config "No plugins" \
        "DOTS_SKIP_MODULES='plugin,enhanced-lazy-tools,lazy-loading' zsh -l -c 'exit 0'"
    
    # Test full configuration
    benchmark_config "Full configuration" \
        "zsh -l -c 'exit 0'"
    
    echo
}

# Test lazy loading effectiveness
test_lazy_loading() {
    log "Testing lazy loading effectiveness"
    echo
    
    # Test startup without lazy loading
    benchmark_config "No lazy loading" \
        "LAZY_LOADING_ENABLED=0 zsh -l -c 'exit 0'"
    
    # Test with lazy loading enabled
    benchmark_config "With lazy loading" \
        "LAZY_LOADING_ENABLED=1 zsh -l -c 'exit 0'"
    
    # Test tool initialization time
    benchmark_config "Docker first use" \
        "zsh -l -c 'docker --version >/dev/null 2>&1; exit 0'"
    
    benchmark_config "kubectl first use" \
        "zsh -l -c 'kubectl version --client >/dev/null 2>&1; exit 0'"
    
    echo
}

# Test project context performance
test_project_contexts() {
    log "Testing project context detection performance"
    echo
    
    # Create temporary test directories
    local temp_dir=$(mktemp -d)
    local original_pwd="$PWD"
    
    # Test different project types
    for project_type in nodejs rust python docker k8s; do
        local project_dir="$temp_dir/$project_type"
        mkdir -p "$project_dir"
        cd "$project_dir"
        
        # Create project-specific files
        case $project_type in
            nodejs)
                echo '{"name":"test"}' > package.json
                ;;
            rust)
                echo '[package]\nname="test"' > Cargo.toml
                ;;
            python)
                echo 'requests==2.25.1' > requirements.txt
                ;;
            docker)
                echo 'FROM ubuntu' > Dockerfile
                ;;
            k8s)
                mkdir -p k8s
                echo 'apiVersion: v1\nkind: Pod' > k8s/pod.yaml
                ;;
        esac
        
        # Benchmark startup in this context
        benchmark_config "$project_type project" \
            "cd '$project_dir' && zsh -l -c 'exit 0'"
        
        cd "$original_pwd"
    done
    
    # Clean up
    rm -rf "$temp_dir"
    echo
}

# Profile with zprofiler
run_profiling() {
    if [[ "$PROFILE_MODE" == "false" ]]; then
        return 0
    fi
    
    log "Running detailed profiling analysis"
    echo
    
    # Profile startup with zprofiler
    log "Startup profiling:"
    ZPROFILER=1 zsh -l -c 'exit 0' 2>&1 | head -20
    echo
    
    # Profile with debugging
    log "Module loading analysis:"
    DOTS_DEBUG=1 zsh -l -c 'exit 0' 2>&1 | grep -E '\[PERF\]|\[LAZY\]|Loading|loaded' | head -15
    echo
}

# Compare different strategies
run_comparison() {
    if [[ "$COMPARE_MODE" == "false" ]]; then
        return 0
    fi
    
    log "Comparing different optimization strategies"
    echo
    
    # Original configuration (simulate old approach)
    log "Strategy comparison:"
    
    # Eager loading simulation
    benchmark_config "Eager loading (old)" \
        "LAZY_LOADING_ENABLED=0 ENHANCED_LAZY_TOOLS=0 zsh -l -c 'exit 0'"
    
    # Basic lazy loading
    benchmark_config "Basic lazy loading" \
        "LAZY_LOADING_ENABLED=1 ENHANCED_LAZY_TOOLS=0 zsh -l -c 'exit 0'"
    
    # Enhanced lazy loading
    benchmark_config "Enhanced lazy loading" \
        "LAZY_LOADING_ENABLED=1 ENHANCED_LAZY_TOOLS=1 zsh -l -c 'exit 0'"
    
    # Context-aware loading
    benchmark_config "Context-aware loading" \
        "PROJECT_CONTEXT_ENABLED=1 zsh -l -c 'exit 0'"
    
    echo
}

# Generate performance report
generate_report() {
    log "Performance Analysis Summary"
    echo "=============================="
    
    echo "Test Configuration:"
    echo "  Iterations: $ITERATIONS"
    echo "  Profile mode: $PROFILE_MODE"
    echo "  Compare mode: $COMPARE_MODE"
    echo "  System: $(uname -s) $(uname -m)"
    echo "  Shell: $(zsh --version)"
    echo
    
    echo "Performance Thresholds:"
    echo -e "  ${GREEN}Excellent${NC}: < 100ms"
    echo -e "  ${BLUE}Good${NC}:      < 300ms" 
    echo -e "  ${YELLOW}Acceptable${NC}: < 500ms"
    echo -e "  ${RED}Needs work${NC}: >= 500ms"
    echo
    
    # Tool usage statistics if available
    if command -v tool-stats >/dev/null 2>&1; then
        echo "Recent tool usage (for optimization guidance):"
        tool-stats 2>/dev/null || echo "  No usage data available"
        echo
    fi
    
    echo "Optimization Recommendations:"
    echo "  1. Focus on tools taking >50ms to initialize"
    echo "  2. Use project context detection for development tools"
    echo "  3. Enable lazy loading for rarely-used tools"
    echo "  4. Consider caching for expensive initializations"
    echo "  5. Profile regularly to catch performance regressions"
    echo
}

# Main execution
main() {
    log "Starting zsh startup performance benchmark"
    echo "=========================================="
    echo
    
    # Verify environment
    if ! command -v zsh >/dev/null 2>&1; then
        log_error "zsh not found in PATH"
        exit 1
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        log_warning "bc not found, some calculations may be less precise"
    fi
    
    # Run benchmark tests
    test_basic_startup
    test_lazy_loading
    test_project_contexts
    
    # Optional detailed analysis
    run_profiling
    run_comparison
    
    # Generate summary
    generate_report
    
    log_success "Benchmark completed successfully"
}

# Execute main function
main "$@"