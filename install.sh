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
readonly XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
readonly XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
readonly XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly GLOBAL_BREWFILE_PATH="${HOME}/.Brewfile"

# Source utilities (utils.zsh has been split into separate modules)
# Define fallback functions for CI environment
if [[ -n "${CI}" ]]; then
    # Minimal logging functions for CI
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_pass() { echo "[PASS] $*"; }
    
    # Minimal platform detection
    is_osx() { [[ "$OSTYPE" == darwin* ]]; }
    is_linux() { [[ "$OSTYPE" == linux* ]]; }
else
    # Load full modules in normal environment
    if [[ -f "${ZMODDIR}/platform.zsh" ]]; then
        source "${ZMODDIR}/platform.zsh"
    fi
    if [[ -f "${ZMODDIR}/logging.zsh" ]]; then
        source "${ZMODDIR}/logging.zsh"
    fi
    if [[ -f "${ZMODDIR}/strings.zsh" ]]; then
        source "${ZMODDIR}/strings.zsh"
    fi
fi

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

    # Check for package manager
    if is_osx; then
        if ! is_exist_command brew; then
            log_fail "Homebrew is not installed. Please install it first."
            log_info "Visit https://brew.sh for installation instructions"
            exit 1
        fi
    elif is_linux; then
        # Check for common Linux package managers
        local has_package_manager=false
        for cmd in apt dnf yum pacman zypper brew; do
            if is_exist_command "$cmd"; then
                has_package_manager=true
                log_info "Found package manager: $cmd"
                break
            fi
        done

        if [[ "$has_package_manager" = false ]]; then
            log_warn "No common package manager found. You may need to manually install dependencies."
        fi
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

    # Create XDG directories
    create_directory "$XDG_CONFIG_HOME"
    create_directory "$XDG_DATA_HOME"
    create_directory "$XDG_CACHE_HOME"
    create_directory "$XDG_STATE_HOME"

    # Create OS-specific font directories
    if is_osx; then
        create_directory "$HOME/Library/Fonts"
    elif is_linux; then
        create_directory "$XDG_DATA_HOME/fonts"
    fi

    log_pass "Directories setup completed"
}

install_fonts() {
    local font_dir="${DOTDIR}/fonts"

    if [[ ! -d "$font_dir" ]] || [[ -z "$(ls -A "$font_dir")" ]]; then
        log_warn "No fonts found to install"
        return
    fi

    if is_osx; then
        log_info "Installing fonts on macOS..."
        cp -r "${font_dir}"/* "$HOME/Library/Fonts/"
        log_pass "Fonts installed to ~/Library/Fonts"
    elif is_linux; then
        log_info "Installing fonts on Linux..."
        cp -r "${font_dir}"/* "$XDG_DATA_HOME/fonts/"

        # Update font cache on Linux
        if is_exist_command fc-cache; then
            fc-cache -fv >/dev/null 2>&1
            log_pass "Fonts installed to $XDG_DATA_HOME/fonts and cache updated"
        else
            log_warn "Fonts installed but fc-cache not found. You may need to update font cache manually."
        fi
    else
        log_info "Unknown OS, skipping font installation"
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

check_dependencies() {
    log_info "Checking for required dependencies..."

    # List of required tools used in dotfiles
    local required_tools=("eza" "bat" "fd" "rg" "fzf" "gh" "lazygit" "nvim" "mise" "delta" "starship")
    local missing_tools=()
    local installed_tools=()

    for tool in "${required_tools[@]}"; do
        if ! is_exist_command "$tool"; then
            missing_tools+=("$tool")
        else
            installed_tools+=("$tool")
        fi
    done

    # Show installed tools
    if [[ ${#installed_tools[@]} -gt 0 ]]; then
        log_pass "Installed tools: ${installed_tools[*]}"
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warn "The following tools are missing:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo
        if is_osx || is_exist_command brew; then
            echo "You can install them using Homebrew:"
            echo "  brew bundle"
            echo "or individually:"
            echo "  brew install ${missing_tools[*]}"
        elif is_linux; then
            echo "Please install them using your package manager."
            if [[ -d "${DOTDIR}/packages" ]]; then
                echo "Package lists are available in: ${DOTDIR}/packages/"
            fi
        fi
        echo
    else
        log_pass "All required dependencies are installed"
    fi
}

print_next_steps() {
    echo
    log_echo "Installation completed successfully!"
    echo
    echo "Next steps:"
    if is_osx || is_exist_command brew; then
        echo "  1. Run 'brew bundle' to install packages from Brewfile"
    else
        echo "  1. Install required packages using your package manager"
    fi
    echo "  2. Restart your terminal or run 'source ~/.zshrc'"
    echo "  3. Open Neovim and run ':Lazy update' to install plugins"
    echo
    echo "Maintenance commands:"
    echo "  - 'brewbundle' to update Brewfile with current packages (macOS/Homebrew)"
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
    check_dependencies

    print_next_steps
}

# Run main function
main "$@"
