# Project Overview

## Purpose

This is a personal dotfiles repository managed with chezmoi for reproducible development environment setup across macOS systems. It provides a sophisticated, performance-optimized shell configuration with dual environment support (personal/business).

## Key Features

- **Chezmoi-based management**: Cross-platform dotfile management with Go templating
- **Performance optimized**: Lazy-loaded zsh configuration with compiled modules (~40-50ms startup)
- **Dual environment support**: Separate configurations for personal and business use via `BUSINESS_USE` env var
- **XDG compliant**: Follows XDG Base Directory Specification
- **Advanced module system**: Sophisticated dependency resolution with metadata management
- **Enhanced lazy loading**: Context-aware tool loading based on project detection

## Tech Stack

- **dotfile management**: chezmoi with Go templates
- **Shell**: Zsh with performance-optimized module system
- **Package management**: Homebrew (non-Rust), Cargo (Rust tools)
- **Runtime management**: mise for version management
- **Editor**: AstroNvim configuration
- **Prompt**: Starship cross-shell prompt
- **Terminal**: Alacritty configuration
- **Development tools**: pnpm, prettier, custom formatters

## Architecture

- **Source directory**: `/Users/ryota/.local/share/chezmoi/` (managed by chezmoi)
- **Target**: User's home directory with XDG-compliant structure
- **Configuration root**: `dot_config/` maps to `~/.config/`
- **Module system**: Advanced zsh modules with dependency resolution in `dot_config/zsh/modules/`
- **Templates**: `.tmpl` files processed with Go templates for environment-specific config
