#!/usr/bin/env bash
# ============================================================================
# Latest NeoVim Installation Script
#
# This script installs the latest version of NeoVim on Linux systems.
# It tries multiple methods to ensure successful installation:
# 1. AppImage (latest, self-contained)
# 2. Package manager fallback
# 3. Build from source (if needed)
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

# Get system architecture
get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) echo "unknown" ;;
    esac
}

# Check NeoVim version
check_nvim_version() {
    if command_exists nvim; then
        local current_version=$(nvim --version | head -1 | cut -d' ' -f2 | sed 's/^v//')
        echo "$current_version"
    else
        echo "not_installed"
    fi
}

# Install NeoVim via AppImage
install_appimage() {
    print_info "Installing NeoVim via AppImage..."
    
    local arch=$(get_arch)
    local install_dir="$HOME/.local/bin"
    local appimage_path="$install_dir/nvim.appimage"
    
    # Create install directory
    mkdir -p "$install_dir"
    
    # Download AppImage based on architecture
    case "$arch" in
        x86_64)
            print_info "Downloading NeoVim AppImage for x86_64..."
            if curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim.appimage" -o "$appimage_path"; then
                chmod +x "$appimage_path"
                
                # Create symlink for easy access
                if [[ -L "$install_dir/nvim" ]]; then
                    rm "$install_dir/nvim"
                fi
                ln -sf "$appimage_path" "$install_dir/nvim"
                
                print_success "NeoVim AppImage installed successfully"
                return 0
            else
                print_error "Failed to download NeoVim AppImage"
                return 1
            fi
            ;;
        aarch64)
            print_warning "AppImage not available for ARM64, trying alternative methods..."
            return 1
            ;;
        *)
            print_warning "Unknown architecture: $arch, trying alternative methods..."
            return 1
            ;;
    esac
}

# Install via package manager with latest repository
install_via_package_manager() {
    print_info "Installing NeoVim via package manager..."
    
    if command_exists apt; then
        print_info "Using apt (Ubuntu/Debian)..."
        
        # Try to add unstable PPA for latest NeoVim
        if sudo add-apt-repository -y ppa:neovim-ppa/unstable 2>/dev/null; then
            print_info "Added NeoVim unstable PPA"
            sudo apt update -qq
            sudo apt install -y neovim
        else
            print_warning "Could not add PPA, installing from default repository"
            sudo apt update -qq
            sudo apt install -y neovim
        fi
        
    elif command_exists dnf; then
        print_info "Using dnf (Fedora/RHEL)..."
        sudo dnf install -y neovim
        
    elif command_exists pacman; then
        print_info "Using pacman (Arch Linux)..."
        sudo pacman -S --noconfirm neovim
        
    elif command_exists zypper; then
        print_info "Using zypper (openSUSE)..."
        sudo zypper install -y neovim
        
    else
        print_error "No supported package manager found"
        return 1
    fi
}

# Install from pre-built binary
install_prebuilt_binary() {
    print_info "Installing NeoVim from pre-built binary..."
    
    local arch=$(get_arch)
    local temp_dir=$(mktemp -d)
    local install_dir="$HOME/.local"
    
    cd "$temp_dir"
    
    # Download and extract binary
    case "$arch" in
        x86_64)
            print_info "Downloading NeoVim binary for Linux x86_64..."
            if curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz" | tar xz; then
                # Move to install location
                if [[ -d "nvim-linux64" ]]; then
                    # Remove existing installation if present
                    if [[ -d "$install_dir/nvim-linux64" ]]; then
                        rm -rf "$install_dir/nvim-linux64"
                    fi
                    
                    mv nvim-linux64 "$install_dir/"
                    
                    # Create symlink
                    mkdir -p "$install_dir/bin"
                    if [[ -L "$install_dir/bin/nvim" ]]; then
                        rm "$install_dir/bin/nvim"
                    fi
                    ln -sf "$install_dir/nvim-linux64/bin/nvim" "$install_dir/bin/nvim"
                    
                    print_success "NeoVim binary installed successfully"
                    cd - >/dev/null
                    rm -rf "$temp_dir"
                    return 0
                fi
            fi
            ;;
        *)
            print_warning "Pre-built binary not available for $arch"
            ;;
    esac
    
    cd - >/dev/null
    rm -rf "$temp_dir"
    return 1
}

# Verify installation
verify_installation() {
    print_info "Verifying NeoVim installation..."
    
    if command_exists nvim; then
        local version=$(nvim --version | head -1)
        print_success "NeoVim installed: $version"
        
        # Test basic functionality
        if echo "print('NeoVim test successful')" | nvim --headless -c "luafile /dev/stdin" -c "quit" 2>/dev/null; then
            print_success "NeoVim functionality test passed"
            return 0
        else
            print_warning "NeoVim installed but functionality test failed"
            return 1
        fi
    else
        print_error "NeoVim installation verification failed"
        return 1
    fi
}

# Main installation function
main() {
    print_info "Installing latest NeoVim..."
    
    # Skip if running on macOS
    if [[ "$(uname -s)" == "Darwin" ]]; then
        print_info "Running on macOS, NeoVim should be installed via Homebrew"
        if command_exists nvim; then
            local version=$(nvim --version | head -1)
            print_success "NeoVim already available: $version"
        else
            print_warning "NeoVim not found. Install via: brew install neovim"
        fi
        return 0
    fi
    
    # Check current version
    local current_version=$(check_nvim_version)
    if [[ "$current_version" != "not_installed" ]]; then
        print_info "Current NeoVim version: v$current_version"
        
        # Offer to upgrade
        read -p "Do you want to upgrade to the latest version? (y/n): " upgrade_choice
        if [[ ! "$upgrade_choice" =~ ^[yY]$ ]]; then
            print_info "Keeping current installation"
            return 0
        fi
    fi
    
    # Try installation methods in order of preference
    local installation_successful=false
    
    # Method 1: AppImage (most reliable for latest version)
    if install_appimage; then
        installation_successful=true
    elif install_prebuilt_binary; then
        # Method 2: Pre-built binary
        installation_successful=true
    elif install_via_package_manager; then
        # Method 3: Package manager (may be older version)
        installation_successful=true
        print_warning "Installed via package manager - may not be the latest version"
    fi
    
    if [[ "$installation_successful" == true ]]; then
        if verify_installation; then
            print_success "NeoVim installation completed successfully!"
            print_info "You may need to restart your shell or run 'source ~/.zshrc'"
        else
            print_error "Installation completed but verification failed"
            return 1
        fi
    else
        print_error "All installation methods failed"
        print_info "Please try manual installation from: https://github.com/neovim/neovim/releases"
        return 1
    fi
}

# Run main function
main "$@"