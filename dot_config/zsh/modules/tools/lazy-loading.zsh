#!/usr/bin/env zsh
# ============================================================================
# Extended Lazy Loading for Development Tools
#
# This module implements context-aware lazy loading for development tools
# to optimize startup performance while maintaining full functionality.
#
# Features:
# - Project-context detection (Node.js, Rust, Python, etc.)
# - Container tools lazy loading (Docker, Kubernetes)
# - Cloud tools optimization (AWS, GCloud)
# - Intelligent completion loading
# ============================================================================

# Module metadata declaration
# Note: declare_module will be called automatically by the loader
# declare_module "lazy-loading" \
#   "depends:platform,core" \
#   "category:tools" \
#   "description:Context-aware lazy loading for development tools" \
#   "provides:project_context,lazy_docker,lazy_kubectl,lazy_cloud_tools"

# Global variables for lazy loading state
typeset -gA LAZY_LOADING_STATE
LAZY_LOADING_STATE[enabled]="${LAZY_LOADING_ENABLED:-1}"
LAZY_LOADING_STATE[debug]="${LAZY_LOADING_DEBUG:-0}"

# Performance tracking
typeset -gA LAZY_LOADING_TIMINGS

# ============================================================================
# Project Context Detection
# ============================================================================

# Detect current project type and set context
detect_project_context() {
    local context=""
    
    # Node.js projects
    if [[ -f "package.json" ]] || [[ -f "pnpm-workspace.yaml" ]] || [[ -f "yarn.lock" ]] || [[ -f "pnpm-lock.yaml" ]]; then
        context="${context:+$context,}nodejs"
    fi
    
    # Rust projects
    if [[ -f "Cargo.toml" ]] || [[ -f "Cargo.lock" ]]; then
        context="${context:+$context,}rust"
    fi
    
    # Python projects
    if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "poetry.lock" ]]; then
        context="${context:+$context,}python"
    fi
    
    # Container/Kubernetes projects
    if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        context="${context:+$context,}docker"
    fi
    
    if [[ -d "k8s" ]] || [[ -f "kubectl.yaml" ]] || [[ -f "kustomization.yaml" ]] || [[ -n "$KUBECONFIG" ]]; then
        context="${context:+$context,}k8s"
    fi
    
    # Cloud projects
    if [[ -f ".gcloudignore" ]] || [[ -d ".gcloud" ]]; then
        context="${context:+$context,}gcp"
    fi
    
    if [[ -f "aws-cli.yaml" ]] || [[ -d ".aws" ]] || [[ -n "$AWS_PROFILE" ]]; then
        context="${context:+$context,}aws"
    fi
    
    # Terraform/Infrastructure
    if [[ -f "*.tf" ]] || [[ -f "terraform.tfvars" ]]; then
        context="${context:+$context,}terraform"
    fi
    
    echo "${context:-generic}"
}

# Check if current context includes specific project type
is_project_context() {
    local project_type="$1"
    local current_context="${PROJECT_CONTEXT:-$(detect_project_context)}"
    
    [[ "$current_context" == *"$project_type"* ]]
}

# Initialize project context on directory change
_update_project_context() {
    PROJECT_CONTEXT="$(detect_project_context)"
    
    if [[ "${LAZY_LOADING_STATE[debug]}" == "1" ]]; then
        echo "[LAZY] Project context: $PROJECT_CONTEXT"
    fi
}

# Hook into directory changes
if [[ "${LAZY_LOADING_STATE[enabled]}" == "1" ]]; then
    chpwd_functions+=(\_update_project_context)
    # Initialize context for current directory
    _update_project_context
fi

# ============================================================================
# Container Tools Lazy Loading
# ============================================================================

# Docker lazy loading with context awareness
_lazy_docker() {
    local args=("$@")
    local start_time="$(date +%s.%3N)"
    
    # Only proceed if Docker is available
    if ! is_exist_command docker; then
        echo "docker: command not found" >&2
        return 127
    fi
    
    # Remove lazy wrapper
    unfunction _lazy_docker docker 2>/dev/null
    
    # Load Docker completion if in relevant context
    if is_project_context "docker" || [[ "${args[1]}" == "completion" ]]; then
        if [[ -n "$ZSH_VERSION" ]]; then
            eval "$(docker completion zsh 2>/dev/null)" || true
        fi
    fi
    
    local end_time="$(date +%s.%3N)"
    LAZY_LOADING_TIMINGS[docker]="$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")"
    
    if [[ "${LAZY_LOADING_STATE[debug]}" == "1" ]]; then
        echo "[LAZY] Docker initialized in ${LAZY_LOADING_TIMINGS[docker]}s"
    fi
    
    # Execute original command
    command docker "${args[@]}"
}

# Docker Compose lazy loading
_lazy_docker_compose() {
    local args=("$@")
    local start_time="$(date +%s.%3N)"
    
    if ! is_exist_command docker-compose; then
        echo "docker-compose: command not found" >&2
        return 127
    fi
    
    unfunction _lazy_docker_compose docker-compose 2>/dev/null
    
    # Load completion if needed
    if is_project_context "docker"; then
        eval "$(docker-compose completion zsh 2>/dev/null)" || true
    fi
    
    local end_time="$(date +%s.%3N)"
    LAZY_LOADING_TIMINGS[docker-compose]="$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")"
    
    command docker-compose "${args[@]}"
}

# ============================================================================
# Kubernetes Tools Lazy Loading
# ============================================================================

# kubectl lazy loading with context awareness
_lazy_kubectl() {
    local args=("$@")
    local start_time="$(date +%s.%3N)"
    
    if ! is_exist_command kubectl; then
        echo "kubectl: command not found" >&2
        return 127
    fi
    
    unfunction _lazy_kubectl kubectl 2>/dev/null
    
    # Load completion if in k8s context or completing
    if is_project_context "k8s" || [[ "${args[1]}" == "completion" ]]; then
        eval "$(kubectl completion zsh 2>/dev/null)" || true
        
        # Set up common aliases after completion loads
        alias k='kubectl'
        alias kg='kubectl get'
        alias kd='kubectl describe'
        alias kdel='kubectl delete'
        alias kap='kubectl apply'
        alias kex='kubectl exec -it'
        alias klog='kubectl logs'
    fi
    
    local end_time="$(date +%s.%3N)"
    LAZY_LOADING_TIMINGS[kubectl]="$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")"
    
    if [[ "${LAZY_LOADING_STATE[debug]}" == "1" ]]; then
        echo "[LAZY] kubectl initialized in ${LAZY_LOADING_TIMINGS[kubectl]}s"
    fi
    
    command kubectl "${args[@]}"
}

# Helm lazy loading
_lazy_helm() {
    local args=("$@")
    
    if ! is_exist_command helm; then
        echo "helm: command not found" >&2
        return 127
    fi
    
    unfunction _lazy_helm helm 2>/dev/null
    
    if is_project_context "k8s"; then
        eval "$(helm completion zsh 2>/dev/null)" || true
    fi
    
    command helm "${args[@]}"
}

# ============================================================================
# Cloud Tools Lazy Loading
# ============================================================================

# AWS CLI lazy loading
_lazy_aws() {
    local args=("$@")
    local start_time="$(date +%s.%3N)"
    
    if ! is_exist_command aws; then
        echo "aws: command not found" >&2
        return 127
    fi
    
    unfunction _lazy_aws aws 2>/dev/null
    
    # Load completion if in AWS context
    if is_project_context "aws" || [[ "${args[1]}" == "completion" ]]; then
        # AWS CLI v2 completion
        if aws --version 2>&1 | grep -q "aws-cli/2"; then
            eval "$(aws --completion)" || true
        else
            # AWS CLI v1 completion
            eval "$(aws completion zsh 2>/dev/null)" || true
        fi
    fi
    
    local end_time="$(date +%s.%3N)"
    LAZY_LOADING_TIMINGS[aws]="$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")"
    
    command aws "${args[@]}"
}

# Google Cloud CLI lazy loading
_lazy_gcloud() {
    local args=("$@")
    local start_time="$(date +%s.%3N)"
    
    if ! is_exist_command gcloud; then
        echo "gcloud: command not found" >&2
        return 127
    fi
    
    unfunction _lazy_gcloud gcloud 2>/dev/null
    
    # Load completion if in GCP context
    if is_project_context "gcp" || [[ "${args[1]}" == "completion" ]]; then
        # gcloud completion is particularly expensive, so only load when needed
        if [[ -f "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc" ]]; then
            source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"
        else
            eval "$(gcloud completion zsh 2>/dev/null)" || true
        fi
    fi
    
    local end_time="$(date +%s.%3N)"
    LAZY_LOADING_TIMINGS[gcloud]="$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")"
    
    command gcloud "${args[@]}"
}

# ============================================================================
# Package Managers Lazy Loading
# ============================================================================

# NPM lazy loading for Node.js projects
_lazy_npm() {
    local args=("$@")
    
    if ! is_exist_command npm; then
        echo "npm: command not found" >&2
        return 127
    fi
    
    # Check if we're in a Node.js project
    if ! is_project_context "nodejs"; then
        echo "npm: not a Node.js project (no package.json found)" >&2
        echo "Use 'command npm' to force execution" >&2
        return 1
    fi
    
    unfunction _lazy_npm npm 2>/dev/null
    
    # Load npm completion
    eval "$(npm completion 2>/dev/null)" || true
    
    command npm "${args[@]}"
}

# Similar pattern for yarn and pnpm
_lazy_yarn() {
    local args=("$@")
    
    if ! is_exist_command yarn; then
        echo "yarn: command not found" >&2
        return 127
    fi
    
    if ! is_project_context "nodejs"; then
        echo "yarn: not a Node.js project" >&2
        echo "Use 'command yarn' to force execution" >&2
        return 1
    fi
    
    unfunction _lazy_yarn yarn 2>/dev/null
    command yarn "${args[@]}"
}

# Enhanced pnpm lazy loading (since completion is already delayed in plugin.zsh)
_lazy_pnpm() {
    local args=("$@")
    
    if ! is_exist_command pnpm; then
        echo "pnpm: command not found" >&2
        return 127
    fi
    
    if ! is_project_context "nodejs"; then
        echo "pnpm: not a Node.js project" >&2
        echo "Use 'command pnpm' to force execution" >&2
        return 1
    fi
    
    unfunction _lazy_pnpm pnpm 2>/dev/null
    command pnpm "${args[@]}"
}

# ============================================================================
# Python Tools Lazy Loading
# ============================================================================

_lazy_poetry() {
    local args=("$@")
    
    if ! is_exist_command poetry; then
        echo "poetry: command not found" >&2
        return 127
    fi
    
    if ! is_project_context "python"; then
        echo "poetry: not a Python project" >&2
        echo "Use 'command poetry' to force execution" >&2
        return 1
    fi
    
    unfunction _lazy_poetry poetry 2>/dev/null
    
    # Load poetry completion
    eval "$(poetry completions zsh 2>/dev/null)" || true
    
    command poetry "${args[@]}"
}

# ============================================================================
# Rust Tools Context Loading
# ============================================================================

_lazy_cargo_context() {
    # Only load cargo-specific tools in Rust projects
    if is_project_context "rust"; then
        # Load Rust-specific aliases and completions
        if is_exist_command cargo; then
            alias cb='cargo build'
            alias ct='cargo test'
            alias cr='cargo run'
            alias cc='cargo check'
            alias cf='cargo fmt'
            alias ccl='cargo clippy'
        fi
        
        # Load additional Rust tools completions if available
        if is_exist_command rustup; then
            eval "$(rustup completions zsh 2>/dev/null)" || true
        fi
    fi
}

# ============================================================================
# Lazy Loading Registration
# ============================================================================

# Register lazy loading wrappers only if tools are available and lazy loading is enabled
if [[ "${LAZY_LOADING_STATE[enabled]}" == "1" ]]; then
    # Container tools
    if is_exist_command docker; then
        function docker() { _lazy_docker "$@"; }
    fi
    
    if is_exist_command docker-compose; then
        function docker-compose() { _lazy_docker_compose "$@"; }
    fi
    
    # Kubernetes tools
    if is_exist_command kubectl; then
        function kubectl() { _lazy_kubectl "$@"; }
    fi
    
    if is_exist_command helm; then
        function helm() { _lazy_helm "$@"; }
    fi
    
    # Cloud tools
    if is_exist_command aws; then
        function aws() { _lazy_aws "$@"; }
    fi
    
    if is_exist_command gcloud; then
        function gcloud() { _lazy_gcloud "$@"; }
    fi
    
    # Package managers (with project context checking)
    if is_exist_command npm; then
        function npm() { _lazy_npm "$@"; }
    fi
    
    if is_exist_command yarn; then
        function yarn() { _lazy_yarn "$@"; }
    fi
    
    if is_exist_command pnpm; then
        function pnpm() { _lazy_pnpm "$@"; }
    fi
    
    # Python tools
    if is_exist_command poetry; then
        function poetry() { _lazy_poetry "$@"; }
    fi
    
    # Hook into directory changes for Rust context
    chpwd_functions+=(\_lazy_cargo_context)
    _lazy_cargo_context  # Initialize for current directory
fi

# ============================================================================
# Utility Functions
# ============================================================================

# Show lazy loading statistics
lazy_loading_stats() {
    echo "Lazy Loading Statistics:"
    echo "========================"
    echo "Status: ${LAZY_LOADING_STATE[enabled]:+enabled|disabled}"
    echo "Current project context: ${PROJECT_CONTEXT:-$(detect_project_context)}"
    echo
    
    if (( ${#LAZY_LOADING_TIMINGS[@]} > 0 )); then
        echo "Tool initialization times:"
        for tool in "${(@k)LAZY_LOADING_TIMINGS}"; do
            local time="${LAZY_LOADING_TIMINGS[$tool]}"
            printf "  %-15s %6.3fs\n" "$tool:" "$time"
        done
    else
        echo "No tools have been lazy-loaded yet."
    fi
}

# Enable/disable lazy loading
lazy_loading_toggle() {
    if [[ "${LAZY_LOADING_STATE[enabled]}" == "1" ]]; then
        LAZY_LOADING_STATE[enabled]="0"
        echo "Lazy loading disabled. Restart shell to take effect."
    else
        LAZY_LOADING_STATE[enabled]="1"
        echo "Lazy loading enabled. Restart shell to take effect."
    fi
}

# Force load all lazy tools (for testing)
lazy_loading_warm_cache() {
    echo "Warming lazy loading cache..."
    local tools=(docker kubectl helm aws gcloud npm yarn pnpm poetry)
    
    for tool in "${tools[@]}"; do
        if (( $+functions[$tool] )) && [[ "$(type -t "$tool")" == "function" ]]; then
            echo "Initializing $tool..."
            "$tool" --help >/dev/null 2>&1 || true
        fi
    done
    
    echo "Cache warming complete."
    lazy_loading_stats
}

# Aliases for convenience
alias lazy-stats='lazy_loading_stats'
alias lazy-toggle='lazy_loading_toggle'
alias lazy-warm='lazy_loading_warm_cache'
