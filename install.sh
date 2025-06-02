#!/bin/bash

set -euo pipefail

# Configuration
readonly GITHUB_USER="paveg"
readonly GITHUB_REPO="dotfiles"
readonly GHQ_ROOT="${HOME}/repos"
readonly DOTDIR="${GHQ_ROOT}/github.com/${GITHUB_USER}/${GITHUB_REPO}"
readonly ZDOTDIR="${DOTDIR}/zsh.d"
readonly ZMODDIR="${ZDOTDIR}/modules"
readonly XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly GLOBAL_BREWFILE_PATH="${HOME}/.Brewfile"

# Source utilities
source "${ZMODDIR}/utils.zsh"

# Helper functions
create_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

create_symlink() {
    local source="$1"
    local target="$2"
    local flags="${3:-sfnv}"
    
    if [[ ! -e "$source" ]]; then
        log_warn "Source does not exist: $source"
        return 1
    fi
    
    ln "-${flags}" "$source" "$target"
    log_info "Linked: $source -> $target"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! is_exist_command brew; then
        log_fail "Homebrew is not installed. Please install it first."
        log_info "Visit https://brew.sh for installation instructions"
        exit 1
    fi
    
    if [[ ! -d "$DOTDIR" ]]; then
        log_fail "Dotfiles directory not found: $DOTDIR"
        log_info "Please clone the repository to the expected location"
        exit 1
    fi
    
    log_pass "Prerequisites check passed"
}

setup_directories() {
    log_info "Setting up directories..."
    
    create_directory "$XDG_CONFIG_HOME"
    create_directory "$HOME/Library/Fonts" # Only needed on macOS, but safe to create
    
    log_pass "Directories setup completed"
}

install_fonts() {
    if is_osx; then
        log_info "Installing fonts on macOS..."
        
        local font_dir="${DOTDIR}/fonts"
        if [[ -d "$font_dir" ]] && [[ -n "$(ls -A "$font_dir")" ]]; then
            cp -r "${font_dir}"/* "$HOME/Library/Fonts/"
            log_pass "Fonts installed successfully"
        else
            log_warn "No fonts found to install"
        fi
    else
        log_info "Skipping font installation (not on macOS)"
    fi
}

setup_homebrew() {
    log_info "Setting up Homebrew configuration..."
    
    local brewfile_source
    if [[ -z "${BUSINESS_USE:-}" ]]; then
        brewfile_source="${DOTDIR}/homebrew/Brewfile"
        log_info "Using personal Brewfile"
    else
        brewfile_source="${DOTDIR}/homebrew/Brewfile.work"
        log_info "Using work Brewfile (BUSINESS_USE is set)"
    fi
    
    create_symlink "$brewfile_source" "$GLOBAL_BREWFILE_PATH"
    log_pass "Homebrew configuration completed"
}

setup_shell_configs() {
    log_info "Setting up shell configurations..."
    
    # Zsh configuration files
    local zsh_files=(".zshenv" ".zshrc" ".zprofile")
    for file in "${zsh_files[@]}"; do
        create_symlink "${ZDOTDIR}/${file}" "${HOME}/${file}"
    done
    
    # Ruby configuration files
    local ruby_files=(".irbrc" ".rdbgrc")
    for file in "${ruby_files[@]}"; do
        local source="${DOTDIR}/ruby/${file}"
        if [[ -f "$source" ]]; then
            create_symlink "$source" "${HOME}/${file}"
        fi
    done
    
    # Environment variables (1Password integration)
    if [[ -f "${DOTDIR}/.env.1password" ]]; then
        create_symlink "${DOTDIR}/.env.1password" "${HOME}/.env.1password"
    fi
    
    log_pass "Shell configurations completed"
}

setup_application_configs() {
    log_info "Setting up application configurations..."
    
    # Define application configurations
    declare -A app_configs=(
        ["git"]="${DOTDIR}/git"
        ["starship.toml"]="${DOTDIR}/starship.toml"
        ["alacritty"]="${DOTDIR}/alacritty"
        ["zellij"]="${DOTDIR}/zellij"
        ["nvim"]="${DOTDIR}/nvim"
        ["lazygit"]="${DOTDIR}/lazygit"
    )
    
    # Create symlinks for each application
    for app in "${!app_configs[@]}"; do
        local source="${app_configs[$app]}"
        local target="${XDG_CONFIG_HOME}/${app}"
        
        if [[ -e "$source" ]]; then
            create_symlink "$source" "$target"
        else
            log_warn "Configuration not found: $source"
        fi
    done
    
    log_pass "Application configurations completed"
}

print_next_steps() {
    echo
    log_echo "Installation completed successfully!"
    echo
    echo "Next steps:"
    echo "  1. Run 'brew bundle' to install packages from Brewfile"
    echo "  2. Restart your terminal or run 'source ~/.zshrc'"
    echo "  3. Open Neovim and run ':Lazy update' to install plugins"
    echo
    echo "Maintenance commands:"
    echo "  - 'brewbundle' to update Brewfile with current packages"
    echo "  - ':AstroUpdate' in Neovim to update AstroNvim"
    echo
}

# Main installation flow
main() {
    log_info "Starting dotfiles installation..."
    echo
    
    check_prerequisites
    setup_directories
    install_fonts
    setup_homebrew
    setup_shell_configs
    setup_application_configs
    
    print_next_steps
}

# Run main function
main "$@"
