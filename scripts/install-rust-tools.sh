#!/usr/bin/env bash
# ============================================================================
# Fast Rust Tools Installation Script
#
# This script installs Rust-based tools in parallel for faster installation.
# It also supports pre-built binaries where available.
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    local color=$1
    local message=$2
    printf "${color}%s${NC}\n" "$message"
}

print_info() { print_status "$BLUE" "ℹ $1"; }
print_success() { print_status "$GREEN" "✓ $1"; }
print_warning() { print_status "$YELLOW" "⚠ $1"; }
print_error() { print_status "$RED" "✗ $1"; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install via pre-built binary (much faster)
install_binary() {
    local tool=$1
    local url=$2
    local binary_name=${3:-$tool}
    
    print_info "Installing $tool via pre-built binary..."
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Download and extract
    if [[ "$url" =~ \.tar\.gz$ ]]; then
        curl -sL "$url" | tar xz
    elif [[ "$url" =~ \.zip$ ]]; then
        curl -sLo temp.zip "$url"
        unzip -q temp.zip
    fi
    
    # Find and install binary
    if [[ -f "$binary_name" ]]; then
        chmod +x "$binary_name"
        mv "$binary_name" "$HOME/.cargo/bin/"
        print_success "Installed $tool (binary)"
    else
        # Try to find in subdirectories
        local found=$(find . -name "$binary_name" -type f | head -1)
        if [[ -n "$found" ]]; then
            chmod +x "$found"
            mv "$found" "$HOME/.cargo/bin/"
            print_success "Installed $tool (binary)"
        else
            print_error "Binary $binary_name not found"
            return 1
        fi
    fi
    
    cd - >/dev/null
    rm -rf "$temp_dir"
}

# Get system info for binary downloads
get_system_info() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    # Normalize architecture names
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) arch="unknown" ;;
    esac
    
    echo "${os}-${arch}"
}

# Install tools with pre-built binaries where available
install_with_binary_fallback() {
    local tool=$1
    local package=${2:-$tool}
    local binary=${3:-$tool}
    
    local system=$(get_system_info)
    
    case "$tool" in
        starship)
            if [[ "$system" =~ darwin ]]; then
                install_binary starship "https://github.com/starship/starship/releases/latest/download/starship-aarch64-apple-darwin.tar.gz" starship
            else
                install_binary starship "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz" starship
            fi
            ;;
        bat)
            if [[ "$system" =~ darwin-aarch64 ]]; then
                install_binary bat "https://github.com/sharkdp/bat/releases/latest/download/bat-v0.24.0-aarch64-apple-darwin.tar.gz" bat
            elif [[ "$system" =~ darwin-x86_64 ]]; then
                install_binary bat "https://github.com/sharkdp/bat/releases/latest/download/bat-v0.24.0-x86_64-apple-darwin.tar.gz" bat
            else
                install_binary bat "https://github.com/sharkdp/bat/releases/latest/download/bat-v0.24.0-x86_64-unknown-linux-gnu.tar.gz" bat
            fi
            ;;
        fd)
            if [[ "$system" =~ darwin ]]; then
                install_binary fd "https://github.com/sharkdp/fd/releases/latest/download/fd-v10.1.0-aarch64-apple-darwin.tar.gz" fd
            else
                install_binary fd "https://github.com/sharkdp/fd/releases/latest/download/fd-v10.1.0-x86_64-unknown-linux-gnu.tar.gz" fd
            fi
            ;;
        ripgrep)
            if [[ "$system" =~ darwin ]]; then
                install_binary rg "https://github.com/BurntSushi/ripgrep/releases/latest/download/ripgrep-14.1.0-aarch64-apple-darwin.tar.gz" rg
            else
                install_binary rg "https://github.com/BurntSushi/ripgrep/releases/latest/download/ripgrep-14.1.0-x86_64-unknown-linux-gnu.tar.gz" rg
            fi
            ;;
        eza)
            if [[ "$system" =~ darwin-aarch64 ]]; then
                install_binary eza "https://github.com/eza-community/eza/releases/latest/download/eza_aarch64-apple-darwin.tar.gz" eza
            elif [[ "$system" =~ darwin-x86_64 ]]; then
                install_binary eza "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-apple-darwin.tar.gz" eza
            elif [[ "$system" =~ linux-aarch64 ]]; then
                install_binary eza "https://github.com/eza-community/eza/releases/latest/download/eza_aarch64-unknown-linux-gnu.tar.gz" eza
            else
                install_binary eza "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz" eza
            fi
            ;;
        *)
            # Fallback to cargo install
            print_warning "No pre-built binary available for $tool, using cargo install..."
            cargo install "$package" --root "$HOME/.cargo" --locked
            ;;
    esac
}

# Parallel cargo install function
parallel_cargo_install() {
    local tools=("$@")
    local pids=()
    
    for tool_spec in "${tools[@]}"; do
        IFS=':' read -r package binary <<< "$tool_spec"
        binary=${binary:-$package}
        
        # Skip if already installed
        if command_exists "$binary"; then
            print_info "$package already installed, skipping..."
            continue
        fi
        
        # Try binary installation first for supported tools
        case "$package" in
            starship|bat|fd-find|ripgrep|eza)
                install_with_binary_fallback "$binary" "$package" "$binary" &
                pids+=($!)
                ;;
            *)
                # Cargo install in background
                (
                    print_info "Installing $package via cargo..."
                    if cargo install "$package" --root "$HOME/.cargo" --locked >/dev/null 2>&1; then
                        print_success "Installed $package"
                    else
                        print_error "Failed to install $package"
                    fi
                ) &
                pids+=($!)
                ;;
        esac
        
        # Limit parallel jobs
        if [[ ${#pids[@]} -ge 4 ]]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
        fi
    done
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Main installation function
main() {
    print_info "Fast Rust tools installation (parallel + pre-built binaries)"
    
    # Ensure cargo bin directory exists
    mkdir -p "$HOME/.cargo/bin"
    
    # Core tools (install these first with binaries)
    print_info "Installing core tools with pre-built binaries..."
    local core_tools=(
        "starship"
        "bat"
        "fd-find:fd"
        "ripgrep:rg"
        "eza"
    )
    
    for tool_spec in "${core_tools[@]}"; do
        IFS=':' read -r package binary <<< "$tool_spec"
        binary=${binary:-$package}
        
        if ! command_exists "$binary"; then
            install_with_binary_fallback "$binary" "$package" "$binary"
        else
            print_info "$binary already installed"
        fi
    done
    
    # Additional tools (install in parallel via cargo)
    print_info "Installing additional tools via cargo (in parallel)..."
    local additional_tools=(
        "atuin"
        "broot"
        "git-delta:delta"
        "zellij"
        "bottom:btm"
        "zoxide"
        "tokei"
        "sd"
        "du-dust:dust"
        "procs"
        "hyperfine"
        "just"
    )
    
    # Ask user if they want to install all additional tools
    echo
    print_warning "Additional tools will be compiled from source (slower)."
    read -p "Install all additional tools? (y/n/select): " choice
    
    case "$choice" in
        y|Y)
            parallel_cargo_install "${additional_tools[@]}"
            ;;
        n|N)
            print_info "Skipping additional tools"
            ;;
        s|select)
            print_info "Select tools to install:"
            local selected_tools=()
            for tool in "${additional_tools[@]}"; do
                IFS=':' read -r package binary <<< "$tool"
                read -p "Install $package? (y/n): " install_choice
                if [[ "$install_choice" =~ ^[yY]$ ]]; then
                    selected_tools+=("$tool")
                fi
            done
            if [[ ${#selected_tools[@]} -gt 0 ]]; then
                parallel_cargo_install "${selected_tools[@]}"
            fi
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
    
    print_success "Installation completed!"
    print_info "Tools installed to: $HOME/.cargo/bin"
}

# Run main function
main "$@"

