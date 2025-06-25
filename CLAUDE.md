# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository managed with [chezmoi](https://www.chezmoi.io/) for reproducible development environment setup across macOS systems. The configuration follows XDG Base Directory Specification and uses Go templates for cross-platform and environment-specific customization.

## Key Commands

### Chezmoi Operations
- `chezmoi status` - Check status of managed files
- `chezmoi apply` - Apply changes from source to target files
- `chezmoi diff` - Show differences between source and target
- `chezmoi edit <file>` - Edit source file (e.g., `chezmoi edit ~/.zshrc`)
- `chezmoi source-path <file>` - Find source path for a target file
- `chezmoi managed` - List all files managed by chezmoi
- `chezmoi init --apply paveg` - Install dotfiles from scratch

### Environment-Specific Setup
- `BUSINESS_USE=1 chezmoi apply` - Apply business/work configurations
- Environment detection is automatic via `.chezmoi.yaml.tmpl`

### Package Management
- `brewbundle` - Update Brewfile with current Homebrew packages (custom alias)
- `brew bundle` - Install packages from Brewfile
- `brew bundle --file=homebrew/Brewfile.work` - Install work-specific packages

### Zsh Performance Monitoring
- `zprofiler` - Profile zsh startup time
- `zshtime` - Measure zsh startup performance

### Neovim/AstroNvim
- `:Lazy update` - Update Neovim plugins
- `:AstroUpdate` - Update AstroNvim packages

## Architecture

The repository uses chezmoi's template system with XDG-compliant structure:

### 1. Chezmoi Structure
- **Source directory**: `/Users/ryota/.local/share/chezmoi/` (managed automatically)
- **Templates**: Files ending in `.tmpl` are processed with Go templates
- **Configuration**: `.chezmoi.yaml.tmpl` defines variables for templates
- **Run-once scripts**: `run_once_*.sh.tmpl` handle automated setup

### 2. XDG Base Directory Layout
All configurations are under `dot_config/` (maps to `~/.config/`):
- `dot_config/zsh/` - Shell configuration with performance optimizations
- `dot_config/git/` - Modular git configuration (main, work, secrets)
- `dot_config/nvim/` - AstroNvim configuration with custom plugins
- `dot_config/starship.toml` - Cross-shell prompt configuration
- `dot_config/alacritty/` - Terminal emulator configuration

### 3. Zsh Performance Architecture
Located in `dot_config/zsh/modules/`, featuring sophisticated lazy loading:

**Core Modules** (loaded in order):
- `platform.zsh` - OS detection and `is_exist_command` utility
- `core.zsh` - Essential zsh settings and history
- Module-specific configs (alias, func, keybind, etc.)

**Performance Features**:
- `.zwc` compilation for faster loading
- Lazy initialization for tools (mise, atuin, fzf)
- Smart session detection (tmux, zellij, nested shells)
- Conditional loading based on shell context

### 4. Template System
Uses Go templates for environment-specific configuration:
- `{{ .business_use }}` - Business vs personal environment detection
- `{{ .chezmoi.os }}` - OS-specific configurations
- `{{ .chezmoi.homeDir }}` - Home directory path
- XDG directory variables for proper path handling

### 5. Automated Setup
- `run_once_before_install-packages.sh.tmpl` - Package installation (Homebrew, etc.)
- `run_once_after_setup-zsh.sh.tmpl` - Zsh configuration and optimization
- Cross-platform package installation with CI skip capabilities

## Important Configuration Details

- All file edits must be done via `chezmoi edit` to maintain source synchronization
- Zsh modules are loaded in specific order; `platform.zsh` must be first
- Git configuration is split into multiple files (main, work settings, secrets)
- Business/personal environment switching via `BUSINESS_USE` environment variable
- Performance optimization through zsh compilation and lazy loading patterns
- Uses mise (formerly rtx) for runtime version management with conditional initialization