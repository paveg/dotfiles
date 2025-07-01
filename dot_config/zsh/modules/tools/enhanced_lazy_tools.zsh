#!/usr/bin/env zsh
# ============================================================================
# Enhanced Lazy Loading for Existing Tools
#
# This module enhances the existing lazy loading patterns for mise, atuin,
# and other tools to provide better performance and context awareness.
# ============================================================================

# Module metadata declaration
declare_module "enhanced_lazy_tools" \
  "depends:platform,core,lazy_loading" \
  "category:tools" \
  "description:Enhanced lazy loading for mise, atuin, and other existing tools" \
  "provides:enhanced_mise_loading,enhanced_atuin_loading,enhanced_starship_loading,tool_stats"

# Ensure we have access to timing functions from lazy_loading module
# If they're not available, define fallback versions
if ! (( $+functions[_get_timestamp] )); then
    _get_timestamp() {
        if [[ "$(uname)" == "Darwin" ]]; then
            if command -v gdate >/dev/null 2>&1; then
                gdate +%s.%3N
            else
                date +%s.%N | cut -c1-13
            fi
        else
            date +%s.%3N
        fi
    }
fi

if ! (( $+functions[_calc_duration] )); then
    _calc_duration() {
        local start_time="$1"
        local end_time="$2"

        if command -v bc >/dev/null 2>&1; then
            echo "$end_time - $start_time" | bc 2>/dev/null || echo "0.000"
        else
            awk "BEGIN { printf \"%.3f\", $end_time - $start_time }" 2>/dev/null || echo "0.000"
        fi
    }
fi

# ============================================================================
# Enhanced Mise Lazy Loading
# ============================================================================

# Improve existing mise lazy loading with better context detection
_enhanced_mise_init() {
    # Check if mise is available
    if ! is_exist_command mise; then
        return 0
    fi

    # Enhanced session detection
    local in_session=false
    if [[ -n "$TMUX" ]] || [[ -n "$ZELLIJ" && "$ZELLIJ" != "0" ]] || [[ "${SHLVL:-1}" -gt 2 ]]; then
        in_session=true
    fi

    # Project-aware loading: immediate loading in projects that need version management
    local needs_immediate_mise=false
    if [[ -f ".mise.toml" ]] || [[ -f ".tool-versions" ]] || [[ -f ".node-version" ]] || [[ -f ".ruby-version" ]] || [[ -f ".python-version" ]]; then
        needs_immediate_mise=true
    fi

    if [[ "$in_session" == "true" ]] || [[ "$needs_immediate_mise" == "true" ]]; then
        # Immediate initialization with performance tracking
        local start_time="$(_get_timestamp)"
        eval "$(mise activate zsh)"
        local end_time="$(_get_timestamp)"

        if [[ -n "$DOTS_DEBUG" ]] && [[ "$DOTS_DEBUG" != "0" ]]; then
            local duration="$(_calc_duration "$start_time" "$end_time")"
            echo "[PERF] mise activated in ${duration}s (immediate: session=$in_session, project=$needs_immediate_mise)"
        fi
    else
        # Enhanced lazy loading with first-use performance tracking
        _lazy_mise() {
            local args=("$@")
            local start_time="$(_get_timestamp)"

            unfunction _lazy_mise mise
            eval "$(mise activate zsh)"

            local end_time="$(_get_timestamp)"
            if [[ -n "$DOTS_DEBUG" ]] && [[ "$DOTS_DEBUG" != "0" ]]; then
                local duration="$(_calc_duration "$start_time" "$end_time")"
                echo "[PERF] mise lazy-loaded in ${duration}s"
            fi

            mise "${args[@]}"
        }
        function mise() { _lazy_mise "$@"; }
    fi
}

# ============================================================================
# Enhanced Atuin Lazy Loading
# ============================================================================

# Improve atuin loading - always load immediately to prevent Ctrl+R crashes
_enhanced_atuin_init() {
    if ! is_exist_command atuin; then
        return 0
    fi

    # Always load atuin immediately to prevent binding conflicts and crashes
    # The performance impact is minimal compared to the stability benefit
    local start_time="$(_get_timestamp)"

    # Initialize atuin with comprehensive error handling
    if eval "$(atuin init zsh)" 2>/dev/null; then
        local end_time="$(_get_timestamp)"
        if [[ -n "$DOTS_DEBUG" ]] && [[ "$DOTS_DEBUG" != "0" ]]; then
            local duration="$(_calc_duration "$start_time" "$end_time")"
            echo "[PERF] atuin initialized immediately in ${duration}s"
        fi
    else
        # If atuin fails to initialize, ensure we have a working Ctrl+R
        if [[ -n "$DOTS_DEBUG" ]] && [[ "$DOTS_DEBUG" != "0" ]]; then
            echo "[WARN] atuin initialization failed, using default history search"
        fi
        bindkey '^r' history-incremental-search-backward
    fi
}

# ============================================================================
# Enhanced Starship Loading
# ============================================================================

# Optimize starship initialization
_enhanced_starship_init() {
    if ! is_exist_command starship; then
        return 0
    fi

    # Starship needs to be loaded early for prompt, but we can optimize it
    local start_time="$(_get_timestamp)"

    # Use cached initialization if available
    local starship_cache="$XDG_CACHE_HOME/zsh/starship.zsh"
    if [[ -f "$starship_cache" ]] && [[ "$starship_cache" -nt "$(command -v starship)" ]]; then
        # Use cached version if it's newer than the starship binary
        source "$starship_cache"
        if [[ -n "$DOTS_DEBUG" ]] && [[ "$DOTS_DEBUG" != "0" ]]; then
            local end_time="$(_get_timestamp)"
            local duration="$(_calc_duration "$start_time" "$end_time")"
            echo "[PERF] starship loaded from cache in ${duration}s"
        fi
    else
        # Generate and cache starship initialization
        eval "$(starship init zsh)"

        # Cache for future use
        if [[ -n "$XDG_CACHE_HOME" ]]; then
            mkdir -p "$(dirname "$starship_cache")"
            starship init zsh > "$starship_cache" 2>/dev/null || true
        fi

        if [[ -n "$DOTS_DEBUG" ]] && [[ "$DOTS_DEBUG" != "0" ]]; then
            local end_time="$(_get_timestamp)"
            local duration="$(_calc_duration "$start_time" "$end_time")"
            echo "[PERF] starship initialized and cached in ${duration}s"
        fi
    fi
}

# ============================================================================
# Enhanced Homebrew Command-Not-Found
# ============================================================================

# Optimize the existing command-not-found handler
_enhanced_command_not_found_init() {
    # Only set up the lazy handler if Homebrew's handler exists
    local homebrew_handler="/opt/homebrew/Library/Taps/homebrew/homebrew-command-not-found/handler.sh"

    if [[ -f "$homebrew_handler" ]]; then
        _lazy_command_not_found_handler() {
            local start_time="$(_get_timestamp)"

            # Replace this function with the real handler
            unfunction command_not_found_handler
            source "$homebrew_handler"

            if [[ -n "$DOTS_DEBUG" ]] && [[ "$DOTS_DEBUG" != "0" ]]; then
                local end_time="$(_get_timestamp)"
                local duration="$(_calc_duration "$start_time" "$end_time")"
                echo "[PERF] command-not-found handler loaded in ${duration}s"
            fi

            # Call the real handler
            command_not_found_handler "$@"
        }
        function command_not_found_handler() { _lazy_command_not_found_handler "$@"; }
    fi
}

# ============================================================================
# Enhanced Plugin Loading Optimization
# ============================================================================

# Function to optimize plugin loading timing based on usage patterns
optimize_plugin_loading() {
    # This will be called by the plugin.zsh module to adjust wait times
    # based on usage patterns and performance requirements

    local -A plugin_priorities=(
        # Core functionality - load quickly
        [zsh-syntax-highlighting]="0"
        [zsh-completions]="0"

        # Productivity - medium priority
        [zsh-autosuggestions]="1"
        [zsh-z]="1"
        [zsh-history-substring-search]="1"

        # Development tools - can wait longer
        [kubectl]="3"
        [docker]="4"
        [gcloud]="5"

        # Rarely used - lowest priority
        [terraform]="6"
        [aws]="6"
    )

    # Export the priorities for use by plugin.zsh
    for plugin priority in "${(@kv)plugin_priorities}"; do
        export "PLUGIN_PRIORITY_${plugin//[^a-zA-Z0-9_]/_}=$priority"
    done
}

# ============================================================================
# Tool Usage Analytics (Optional)
# ============================================================================

# Track tool usage to optimize lazy loading decisions
_track_tool_usage() {
    local tool="$1"
    local usage_file="$XDG_CACHE_HOME/zsh/tool_usage.log"

    if [[ -n "$XDG_CACHE_HOME" ]] && [[ "${TRACK_TOOL_USAGE:-0}" == "1" ]]; then
        mkdir -p "$(dirname "$usage_file")"
        echo "$(date +%s) $tool" >> "$usage_file"
    fi
}

# Get most used tools for optimization hints
get_tool_usage_stats() {
    local usage_file="$XDG_CACHE_HOME/zsh/tool_usage.log"

    if [[ -f "$usage_file" ]]; then
        echo "Tool usage statistics (last 30 days):"
        echo "======================================"

        # Show usage from last 30 days
        local cutoff_date=$(($(date +%s) - 30*24*3600))
        awk -v cutoff="$cutoff_date" '$1 > cutoff { print $2 }' "$usage_file" | \
            sort | uniq -c | sort -nr | head -10 | \
            while read count tool; do
                printf "  %-15s %3d uses\n" "$tool" "$count"
            done
    else
        echo "No usage statistics available. Set TRACK_TOOL_USAGE=1 to enable."
    fi
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize enhanced lazy loading for existing tools
_enhanced_mise_init
# _enhanced_atuin_init  # Disabled: atuin is now initialized directly in plugin.zsh
_enhanced_starship_init
_enhanced_command_not_found_init

# Optimize plugin loading priorities
optimize_plugin_loading

# Aliases for new functionality
alias tool-stats='get_tool_usage_stats'
alias optimize-plugins='optimize_plugin_loading'
