# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/) for reproducible development environment setup across macOS systems.

## Features

- **Chezmoi-based**: Cross-platform dotfile management with templating
- **Performance optimized**: Lazy-loaded zsh configuration with compiled modules
- **Dual environment**: Separate configurations for personal and business use
- **XDG compliant**: Follows XDG Base Directory Specification

## Tools

- [chezmoi](https://www.chezmoi.io/) - Dotfile management
- [Homebrew](https://brew.sh/) - Package management
- [AstroNvim](https://astronvim.com/) - Neovim configuration
- [Zsh](https://www.zsh.org/) - Shell with performance optimizations
- [Starship](https://starship.rs/) - Cross-shell prompt

## Installation

1. Install Homebrew:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. Install and apply dotfiles:
```bash
# Install chezmoi and apply dotfiles in one command
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply paveg

# For business environment
BUSINESS_USE=1 chezmoi apply
```

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
