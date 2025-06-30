# Documentation

This directory contains comprehensive documentation for the dotfiles repository.

## Core Documentation

- **[LAZY_LOADING.md](LAZY_LOADING.md)** - Enhanced lazy loading system for zsh startup optimization
- **[COMPLETION_ENHANCEMENTS.md](COMPLETION_ENHANCEMENTS.md)** - Zsh completion system improvements and optimizations
- **[TESTING.md](TESTING.md)** - Testing procedures and validation scripts for the dotfiles system

## Quick Reference

### Performance Optimization

- See [LAZY_LOADING.md](LAZY_LOADING.md) for detailed information about the context-aware lazy loading system
- Performance commands: `lazy-stats`, `lazy-warm`, `mise run benchmark`
- Environment variables: `LAZY_LOADING_ENABLED`, `LAZY_LOADING_DEBUG`, `TRACK_TOOL_USAGE`

### Development

- See [TESTING.md](TESTING.md) for testing procedures and validation
- Format code: `mise run format`, `mise run format-md`, `mise run format-zsh`
- Test modules: `./tests/test_runner.sh`, `mise run test`

### Advanced Features

- See [COMPLETION_ENHANCEMENTS.md](COMPLETION_ENHANCEMENTS.md) for completion system details
- Project context detection for automatic tool loading
- Hybrid formatting system (prettier + custom zsh formatter)

## Main Documentation

For general setup and usage, see the main [README.md](../README.md) and [CLAUDE.md](../CLAUDE.md) files in the repository root.