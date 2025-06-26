# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/) for reproducible development environment setup across macOS systems.

## Features

- **Chezmoi-based**: Cross-platform dotfile management with templating
- **Performance optimized**: Lazy-loaded zsh configuration with compiled modules
- **Dual environment**: Separate configurations for personal and business use
- **XDG compliant**: Follows XDG Base Directory Specification

## Tools

- [chezmoi](https://www.chezmoi.io/) - Dotfile management
- [Homebrew](https://brew.sh/) - Package management (non-Rust tools)
- [Cargo](https://doc.rust-lang.org/cargo/) - Rust tools installation
- [mise](https://mise.jdx.dev/) - Runtime version management (including Rust)
- [AstroNvim](https://astronvim.com/) - Neovim configuration
- [Zsh](https://www.zsh.org/) - Shell with performance optimizations
- [Starship](https://starship.rs/) - Cross-shell prompt

## Installation

**One-command install:**

```bash

# Personal environment

curl -fsSL https://raw.githubusercontent.com/paveg/dotfiles/main/install | bash

# Business environment

BUSINESS_USE=1 curl -fsSL https://raw.githubusercontent.com/paveg/dotfiles/main/install | bash
```

**Alternative (using chezmoi directly):**
```bash

# Personal environment

sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply paveg

# Business environment

BUSINESS_USE=1 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply paveg
```

The installation script automatically handles:
- **macOS**: Homebrew installation and package management via Brewfile
- **Linux**: Native package manager detection (apt/dnf/pacman) and CLI tools installation
- Environment-specific configuration (personal/business)
- Zsh setup and optimization
- Cross-platform compatibility

## Maintenance

### Package Management

```bash

# Update Brewfile with current packages

brewbundle

# Install packages from Brewfile

brew bundle
brew bundle --file=homebrew/Brewfile.work  # For business packages
```

### Chezmoi Operations

```bash

# Check status

chezmoi status

# Apply changes

chezmoi apply

# Edit configuration

chezmoi edit ~/.zshrc
```

### Performance Monitoring

```bash

# Profile zsh startup time

zprofiler

# Measure startup performance

zshtime
```

### Rust Tools Management

```bash

# Install/update Rust tools (fast: pre-built binaries + parallel compilation)

~/.local/share/chezmoi/scripts/install-rust-tools.sh

# Edit tools list (categorized by ESSENTIAL/CORE/DEVELOPMENT/OPTIONAL)

chezmoi edit ~/.local/share/chezmoi/packages/rust-tools.txt

# Manage Rust version with mise

mise install rust@stable
mise use rust@stable
```
