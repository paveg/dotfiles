# Codebase Structure

## Repository Root

```
├── dot_config/           # Maps to ~/.config/ (XDG-compliant)
│   ├── zsh/             # Zsh configuration with advanced module system
│   ├── nvim/            # AstroNvim configuration
│   ├── git/             # Modular git configuration
│   ├── alacritty/       # Terminal emulator config
│   └── starship.toml    # Cross-shell prompt
├── scripts/             # Utility scripts
├── tests/               # Test suites
├── homebrew/            # Brewfiles for package management
├── packages/            # Package definitions (rust-tools.txt)
├── docs/                # Documentation
├── mise.toml            # Task runner configuration (not managed by chezmoi)
├── package.json         # Local dev dependencies (not managed by chezmoi)
└── CLAUDE.md           # Comprehensive development guide
```

## Zsh Module Architecture (`dot_config/zsh/modules/`)

```
├── core/                # Essential functionality (MUST load first)
│   ├── platform.zsh     # OS detection, is_exist_command (FIRST)
│   ├── core.zsh         # Essential functions, completion init
│   ├── path.zsh         # PATH management system
│   ├── metadata.zsh     # Module metadata system
│   └── loader.zsh       # Module loading system
├── config/              # Basic shell configuration
│   └── config.zsh       # Zsh options, history
├── utils/               # Utility functions
│   ├── func.zsh         # Helper functions (opr, profiling)
│   └── alias.zsh        # Command aliases
├── tools/               # Tool integrations
│   ├── plugin.zsh       # Zinit plugin management
│   ├── lazy-loading.zsh # Enhanced lazy loading system
│   └── enhanced-lazy-tools.zsh # Context-aware tool loading
├── ui/                  # User interface
│   └── keybind.zsh      # Key bindings
└── local/               # Local machine-specific config
    └── local.zsh        # Not tracked by git
```

## Key Configuration Files

- `.chezmoi.yaml.tmpl`: Chezmoi configuration with environment detection
- `dot_zshenv.tmpl`: Early PATH and environment setup
- `dot_config/zsh/dot_zshrc.tmpl`: Main zsh configuration entry point
- `dot_config/zsh/init.zsh`: Module system initialization

## Template System

- Files ending in `.tmpl` are processed with Go templates
- Variables from `.chezmoi.yaml.tmpl`: `{{ .business_use }}`, `{{ .chezmoi.os }}`, etc.
- XDG directory variables for proper path handling
- Architecture detection for Apple Silicon vs Intel

## Scripts Directory

- `install_rust_tools.sh`: Optimized Rust tools installation
- `format_zsh.sh`: Custom zsh formatter
- `test_comprehensive.sh`: Main test suite
- `benchmark_startup.sh`: Performance benchmarking

## Testing Infrastructure

- `tests/test_comprehensive.sh`: 71+ comprehensive tests
- `tests/test_lazy_loading.sh`: 12 specialized lazy loading tests
- `tests/test_runner.sh`: Legacy validation suite
- Integration with `mise run` tasks for easy execution
