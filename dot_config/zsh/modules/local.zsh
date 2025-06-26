#!/usr/bin/env zsh
# ============================================================================
# Local Configuration Loader
#
# This module loads PC-specific configurations that are not tracked by git.
# Useful for work machines, personal preferences, or sensitive configurations.
#
# Configuration locations (checked in order):
# 1. ~/.config/zsh/local.zsh (XDG standard location)
# 2. ~/.zsh_local (traditional location)
# 3. ~/.config/zsh/local/ directory (for multiple files)
#
# Example use cases:
# - Work-specific aliases and functions
# - Machine-specific environment variables
# - Private API keys or credentials
# - Custom PATH modifications
# - Local development configurations
# ============================================================================

# Load local configuration files
load_local_config() {
    local config_loaded=false

    # 1. Check for single local config file in XDG location
    if [[ -f "$ZDOTDIR/local.zsh" ]]; then
        source "$ZDOTDIR/local.zsh"
        config_loaded=true
        [[ -n "$ZSHRC_DEBUG" ]] && echo "✓ Loaded local config: $ZDOTDIR/local.zsh"
    fi

    # 2. Check for traditional location
    if [[ -f "$HOME/.zsh_local" ]]; then
        source "$HOME/.zsh_local"
        config_loaded=true
        [[ -n "$ZSHRC_DEBUG" ]] && echo "✓ Loaded local config: $HOME/.zsh_local"
    fi

    # 3. Check for local directory with multiple files
    if [[ -d "$ZDOTDIR/local" ]]; then
        for local_file in "$ZDOTDIR/local"/*.zsh(N); do
            if [[ -r "$local_file" ]]; then
                source "$local_file"
                config_loaded=true
                [[ -n "$ZSHRC_DEBUG" ]] && echo "✓ Loaded local config: $local_file"
            fi
        done
    fi

    # Optional: Set indicator for other scripts
    if [[ "$config_loaded" == "true" ]]; then
        export LOCAL_CONFIG_LOADED=1
    fi
}

# Create local config template function
create_local_template() {
    local template_path="$ZDOTDIR/local.zsh"

    if [[ -f "$template_path" ]]; then
        echo "Local config already exists: $template_path"
        return 1
    fi

    cat > "$template_path" << 'EOF'
#!/usr/bin/env zsh
# ============================================================================
# Local Machine Configuration
#
# This file contains machine-specific configurations that are not tracked
# by git. It's safe to add sensitive information or personal preferences here.
# ============================================================================

# Example: Work-specific aliases
# alias work-deploy='kubectl apply -f k8s/'
# alias work-logs='kubectl logs -f deployment/app'

# Example: Environment variables
# export WORK_API_KEY="your-secret-key"
# export COMPANY_DOMAIN="company.com"

# Example: Custom PATH additions
# path_prepend "$HOME/work-tools/bin"

# Example: Work-specific functions
# work_connect() {
#     ssh user@work-server.company.com
# }

# Example: Machine-specific settings
# export EDITOR="code"  # Use VS Code on this machine
# export BROWSER="chrome"

# Example: Conditional loading based on hostname
# if [[ "$(hostname)" == "work-laptop" ]]; then
#     export BUSINESS_USE=1
#     alias ll='ls -la --color=auto'
# fi

# Example: Git configuration overrides
# git config --global user.email "work.email@company.com"

echo "Local configuration loaded for $(hostname)"
EOF

    echo "Created local config template: $template_path"
    echo "Edit this file to add your machine-specific configurations."
}

# Load local configurations
load_local_config
