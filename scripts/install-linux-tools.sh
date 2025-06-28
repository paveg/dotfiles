#!/usr/bin/env bash
# Unified installer for tools that require special installation on Linux

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Determine system architecture
get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armv7) echo "arm" ;;
        *) echo "$arch" ;;
    esac
}

# Create necessary directories
mkdir -p "$HOME/.local/bin"

# GitHub CLI (gh) installation
install_gh() {
    log_info "Installing GitHub CLI (gh)..."
    
    if command -v gh >/dev/null 2>&1; then
        log_info "gh is already installed: $(command -v gh)"
        return 0
    fi
    
    # Try package manager first
    if command -v apt-get >/dev/null 2>&1; then
        log_info "Installing gh via apt..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update && sudo apt install gh -y
    elif command -v dnf >/dev/null 2>&1; then
        log_info "Installing gh via dnf..."
        sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
        sudo dnf install gh -y
    else
        # Fallback to binary installation
        log_info "Installing gh from binary..."
        local version=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
        local arch=$(get_arch)
        local url="https://github.com/cli/cli/releases/download/v${version}/gh_${version}_linux_${arch}.tar.gz"
        
        local temp_dir=$(mktemp -d)
        curl -L "$url" -o "${temp_dir}/gh.tar.gz"
        tar -xzf "${temp_dir}/gh.tar.gz" -C "${temp_dir}"
        mv "${temp_dir}/gh_${version}_linux_${arch}/bin/gh" "$HOME/.local/bin/"
        chmod +x "$HOME/.local/bin/gh"
        rm -rf "${temp_dir}"
    fi
    
    if command -v gh >/dev/null 2>&1; then
        log_info "✅ gh installed successfully"
    else
        log_error "Failed to install gh"
        return 1
    fi
}

# mise installation
install_mise() {
    log_info "Installing mise..."
    
    if command -v mise >/dev/null 2>&1; then
        log_info "mise is already installed: $(command -v mise)"
        return 0
    fi
    
    # Use official installer
    curl https://mise.run | sh
    
    if [[ -f "$HOME/.local/bin/mise" ]]; then
        log_info "✅ mise installed successfully"
    else
        log_error "Failed to install mise"
        return 1
    fi
}

# ghq installation
install_ghq() {
    log_info "Installing ghq..."
    
    if command -v ghq >/dev/null 2>&1; then
        log_info "ghq is already installed: $(command -v ghq)"
        return 0
    fi
    
    local arch=$(get_arch)
    local version=$(curl -s https://api.github.com/repos/x-motemen/ghq/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    
    if [[ -z "$version" ]]; then
        log_error "Failed to get latest ghq version"
        return 1
    fi
    
    log_info "Installing ghq v${version} for ${arch}..."
    
    local url="https://github.com/x-motemen/ghq/releases/download/v${version}/ghq_linux_${arch}.zip"
    local temp_dir=$(mktemp -d)
    
    curl -L "$url" -o "${temp_dir}/ghq.zip"
    unzip -q "${temp_dir}/ghq.zip" -d "${temp_dir}"
    
    if [[ -f "${temp_dir}/ghq" ]]; then
        mv "${temp_dir}/ghq" "$HOME/.local/bin/ghq"
        chmod +x "$HOME/.local/bin/ghq"
        rm -rf "${temp_dir}"
        log_info "✅ ghq installed successfully"
    else
        rm -rf "${temp_dir}"
        log_error "Failed to install ghq"
        return 1
    fi
}

# delta installation
install_delta() {
    log_info "Installing delta..."
    
    if command -v delta >/dev/null 2>&1; then
        log_info "delta is already installed: $(command -v delta)"
        return 0
    fi
    
    local arch=$(get_arch)
    local version=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$version" ]]; then
        log_error "Failed to get latest delta version"
        return 1
    fi
    
    log_info "Installing delta ${version} for ${arch}..."
    
    local url="https://github.com/dandavison/delta/releases/download/${version}/delta-${version}-x86_64-unknown-linux-gnu.tar.gz"
    if [[ "$arch" == "arm64" ]] || [[ "$arch" == "aarch64" ]]; then
        url="https://github.com/dandavison/delta/releases/download/${version}/delta-${version}-aarch64-unknown-linux-gnu.tar.gz"
    fi
    
    local temp_dir=$(mktemp -d)
    curl -L "$url" -o "${temp_dir}/delta.tar.gz"
    tar -xzf "${temp_dir}/delta.tar.gz" -C "${temp_dir}"
    
    local delta_binary=$(find "${temp_dir}" -name "delta" -type f -executable | head -1)
    if [[ -n "$delta_binary" ]]; then
        mv "$delta_binary" "$HOME/.local/bin/delta"
        chmod +x "$HOME/.local/bin/delta"
        rm -rf "${temp_dir}"
        log_info "✅ delta installed successfully"
    else
        rm -rf "${temp_dir}"
        log_error "Failed to install delta"
        return 1
    fi
}

# lazygit installation
install_lazygit() {
    log_info "Installing lazygit..."
    
    if command -v lazygit >/dev/null 2>&1; then
        log_info "lazygit is already installed: $(command -v lazygit)"
        return 0
    fi
    
    local arch=$(get_arch)
    local version=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    
    if [[ -z "$version" ]]; then
        log_error "Failed to get latest lazygit version"
        return 1
    fi
    
    log_info "Installing lazygit v${version} for ${arch}..."
    
    local url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_x86_64.tar.gz"
    if [[ "$arch" == "arm64" ]] || [[ "$arch" == "aarch64" ]]; then
        url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_arm64.tar.gz"
    fi
    
    local temp_dir=$(mktemp -d)
    curl -L "$url" -o "${temp_dir}/lazygit.tar.gz"
    tar -xzf "${temp_dir}/lazygit.tar.gz" -C "${temp_dir}"
    
    if [[ -f "${temp_dir}/lazygit" ]]; then
        mv "${temp_dir}/lazygit" "$HOME/.local/bin/lazygit"
        chmod +x "$HOME/.local/bin/lazygit"
        rm -rf "${temp_dir}"
        log_info "✅ lazygit installed successfully"
    else
        rm -rf "${temp_dir}"
        log_error "Failed to install lazygit"
        return 1
    fi
}

# Main installation logic
main() {
    log_info "Starting Linux tools installation..."
    
    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        # Install all tools by default
        TOOLS=("gh" "mise" "ghq" "delta" "lazygit")
    else
        TOOLS=("$@")
    fi
    
    # Install requested tools
    for tool in "${TOOLS[@]}"; do
        case "$tool" in
            gh)
                install_gh || log_warn "Failed to install gh"
                ;;
            mise)
                install_mise || log_warn "Failed to install mise"
                ;;
            ghq)
                install_ghq || log_warn "Failed to install ghq"
                ;;
            delta)
                install_delta || log_warn "Failed to install delta"
                ;;
            lazygit)
                install_lazygit || log_warn "Failed to install lazygit"
                ;;
            *)
                log_warn "Unknown tool: $tool"
                ;;
        esac
    done
    
    log_info "Installation complete!"
    
    # Verify PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_warn "Please ensure ~/.local/bin is in your PATH"
    fi
}

# Run main function
main "$@"