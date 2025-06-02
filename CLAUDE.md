# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository that manages configuration for various development tools on macOS. The configurations are organized by tool and use symbolic links installed via `install.sh`.

## Key Commands

### Installation and Setup
- `./install.sh` - Install all dotfiles (creates symlinks to appropriate locations)
- `BUSINESS_USE=1 ./install.sh` - Install with business/work-specific configurations

### Maintenance Commands
- `brewbundle` - Update Brewfile with current Homebrew packages (custom alias)
- `brew bundle` - Install packages from Brewfile
- `brew bundle --file=homebrew/Brewfile.work` - Install work-specific packages

### Neovim/AstroNvim
- `:Lazy update` - Update Neovim plugins (run inside nvim)
- `:AstroUpdate` - Update AstroNvim packages (run inside nvim)

### Zsh Performance
- `zprofiler` - Profile zsh startup time
- `zshtime` - Measure zsh startup performance

## Architecture

The repository follows a modular structure where each tool has its own directory:

1. **Zsh Configuration** (`zsh.d/modules/`): Modular configuration split into:
   - `core.zsh` - Essential zsh settings and history configuration
   - `config.zsh` - Tool-specific configurations (fzf, git-delta, mise, etc.)
   - `plugin.zsh` - Zsh plugin management via sheldon
   - `alias.zsh` - Command aliases and custom functions
   - `func.zsh` - Utility functions (opr for 1Password, rub for git branch cleanup)
   - `keybind.zsh` - Key binding configurations
   - `utils.zsh` - Helper utilities and environment setup

2. **Installation Logic**: The `install.sh` script handles:
   - XDG directory creation
   - Symbolic link management
   - Font installation on macOS
   - Environment variable setup (especially for business use)

3. **Dual Environment Support**: Separate configurations for personal and work machines:
   - `homebrew/Brewfile` - Personal packages
   - `homebrew/Brewfile.work` - Work-specific packages
   - Environment detection via `BUSINESS_USE` variable

## Important Configuration Details

- Git configuration is modular with separate files for main settings, work settings (freee), and secrets
- The repository uses mise (formerly rtx) for runtime version management
- Neovim uses AstroNvim distribution with custom configurations in `nvim/lua/plugins/`
- Compiled zsh files (.zwc) are generated for performance optimization