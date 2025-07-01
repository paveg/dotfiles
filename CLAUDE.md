# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Note**: This is the source CLAUDE.md file managed by chezmoi. When working with dotfiles, always edit files using `chezmoi edit` to ensure changes are properly tracked.

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
- `curl -fsSL https://raw.githubusercontent.com/paveg/dotfiles/main/install | bash` - One-command install (personal)
- `BUSINESS_USE=1 curl -fsSL https://raw.githubusercontent.com/paveg/dotfiles/main/install | bash` - One-command install (business)

### Environment-Specific Setup

- `BUSINESS_USE=1 chezmoi apply` - Apply business/work configurations
- Environment detection is automatic via `.chezmoi.yaml.tmpl`

### Package Management

- `brewbundle` - Update current Brewfile (respects BUSINESS_USE environment)
- `brewbundle_personal` - Update personal Brewfile specifically
- `brewbundle_work` - Update work Brewfile specifically
- `brewbundle_diff` - Show differences between personal and work Brewfiles
- `brew bundle` - Install packages from Brewfile
- `brew bundle --file=homebrew/Brewfile.work` - Install work-specific packages

### Zsh Performance Monitoring

- `zprofiler` - Profile zsh startup time
- `zshtime` - Measure zsh startup performance

### Tmux Auto-start (Linux)

- **Automatic tmux on SSH**: Automatically starts or attaches to tmux sessions on Linux when connecting via SSH
- **Control variables**:
  - `DISABLE_AUTO_TMUX=1` - Disable automatic tmux startup
  - `AUTO_TMUX=1` - Force automatic tmux startup (even in non-SSH sessions)
- **Smart detection**: Only activates for SSH sessions, skips CI/Docker environments
- **Session management**: Attaches to existing sessions or creates new ones

### Neovim/AstroNvim

- `:Lazy update` - Update Neovim plugins
- `:AstroUpdate` - Update AstroNvim packages

### Formatting System

- `mise run format` - Format all files (markdown with prettier, zsh with custom formatter)
- `mise run format-md` - Format only markdown files using prettier
- `mise run format-zsh` - Format only zsh files using custom formatter (handles complex zsh syntax)
- `mise run format-check` - Check formatting without making changes
- `pnpm run format:md` - Alternative: format markdown via pnpm
- `pnpm run format:zsh` - Alternative: format zsh via pnpm

### Enhanced Lazy Loading System

- `lazy-stats` - Show lazy loading statistics and timing information
- `lazy-toggle` - Enable/disable lazy loading system
- `lazy-warm` - Pre-initialize all lazy tools for testing
- `tool-stats` - Display tool usage analytics for optimization
- `mise run test` - Test lazy loading module functionality
- `mise run benchmark` - Benchmark zsh startup time (5 iterations)

### Testing and Development

- `mise run test` - Run comprehensive test suite (71+ tests covering syntax, functions, performance, integration)
- `mise run test-lazy` - Run specialized lazy loading tests (12 tests with performance validation)
- `mise run benchmark` - Benchmark zsh startup time (5 iterations with detailed timing)
- `./tests/test_runner.sh` - Run legacy dotfiles test suite (validates zsh syntax, directory structure, essential files)
- `./scripts/format_zsh.sh -d dot_config/zsh -r` - Format zsh configuration files for consistency
- `./scripts/install_rust_tools.sh` - Install/update Rust-based development tools via cargo
- `./scripts/install_neovim_latest.sh` - Install latest NeoVim on Linux (AppImage, binary, or package manager)
- `chezmoi add <file>` - Add a file to chezmoi management after editing

### Local Development Environment

- `pnpm install` - Install local development dependencies (prettier, etc.)
- `mise install` - Install mise-managed tools (shfmt, etc.)
- Files NOT managed by chezmoi: `mise.toml`, `package.json`, `pnpm-lock.yaml`, `node_modules/`, `.prettierrc`

### Rust Tools Management

- **Installation**: `./scripts/install_rust_tools.sh` - Uses pre-built binaries + parallel cargo install for optimal speed
- **Configuration**: Edit `packages/rust-tools.txt` to add/remove tools (categorized by ESSENTIAL/CORE/DEVELOPMENT/OPTIONAL)
- **Selective Install**: Interactive selection during installation
- **Update**: Run the install script again to update all tools to latest versions
- **Rust version**: Managed via mise (see `~/.config/mise/config.toml`)

**Installation Features:**

- Essential tools (starship, bat, fd, ripgrep, eza): Pre-built binaries (~30 seconds)
- Additional tools: Parallel compilation for speed
- Interactive selection for additional tools

### NeoVim Installation

- **Latest Version**: `./scripts/install_neovim_latest.sh` - Installs latest NeoVim on Linux systems
- **Multi-method approach**: AppImage (preferred) → Pre-built binary → Package manager fallback
- **Cross-platform**: Handles x86_64 and ARM64 architectures
- **Verification**: Tests installation and basic functionality

**Installation Methods Priority:**

1. AppImage (latest, self-contained, x86_64 only)
1. Pre-built binary from GitHub releases
1. Package manager with latest repository (fallback)

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

### 3. Advanced Module System Architecture

Located in `dot_config/zsh/modules/`, featuring sophisticated dependency resolution, metadata management, and performance optimization:

**Module System Components**:

1. **Metadata System** (`metadata.zsh`): Advanced module management using associative arrays to track dependencies, categories, loading states, and performance metrics. Each module declares itself via `declare_module` with structured metadata.

2. **Dependency Resolution** (`init.zsh`): Topological sorting with circular dependency detection. Categorized loading (core, config, utils, ui, tools, experimental) with intelligent fallback to legacy flat structure.

3. **Enhanced Module Loader** (`loader.zsh`): Sophisticated loading system with force reload capabilities, dependent module management, and comprehensive validation including circular dependency detection.

**Advanced Features**:

- Module filtering via `DOTS_SKIP_MODULES`/`DOTS_ONLY_MODULES`
- Dependency graph visualization and introspection tools
- Performance tracking with sub-millisecond timing
- Module compilation (.zwc) optimization
- Comprehensive debugging capabilities

**Core Module Loading Order** (critical sequence):

1. `platform.zsh` - OS detection and `is_exist_command` utility (must be first)
1. `core.zsh` - Essential functions (zcompare, load, init_completion)
1. `path.zsh` - Comprehensive PATH management system
1. `config.zsh` - Basic zsh options and history
1. `alias.zsh` - Command aliases with existence checking
1. `func.zsh` - Utility functions (opr, rub, profiling tools)
1. `keybind.zsh` - Key bindings
1. `plugin.zsh` - Zinit plugin management with aggressive performance tuning
1. `local.zsh` - Machine-specific configurations (not tracked by git)

**Advanced Performance Optimizations**:

1. **Intelligent PATH Management** (`path.zsh`):

- `path_prepend()` and `path_append()` functions prevent duplicates
- Architecture-aware Homebrew path detection (ARM64 vs x86_64)
- Language-specific tool paths in priority order (Rust, Go, Node.js, Python, Ruby)
- XDG-compliant mise shims integration
- PATH debugging utilities (`path_show`, `path_clean`, `path_check`)

1. **Completion System Optimization**:

- Cached completion initialization via `init_completion()` in `core.zsh`
- Deferred completion loading through zinit's turbo mode
- Eval-based completions for modern tools (mise, chezmoi, pnpm, gh, atuin)
- Strategic timing delays (wait"0", wait"2", wait"3") to prevent startup blocking
- XDG-compliant cache directory (`$XDG_CACHE_HOME/zsh/zcompdump`)

1. **Enhanced Lazy Loading System**:

- **Project context detection**: Automatically detects Node.js, Rust, Python, Docker, K8s projects
- **Context-aware tool loading**: Tools only load when relevant (e.g., docker in projects with Dockerfile)
- **Performance tracking**: Detailed timing with `LAZY_LOADING_TIMINGS` array
- **Session-aware initialization**: Different behavior in tmux/zellij vs standalone shells
- **Tool usage analytics**: Optional tracking with `TRACK_TOOL_USAGE=1`
- **Smart completion loading**: Expensive completions (gcloud, aws) only load when needed
- **Package manager validation**: npm/yarn/pnpm check for package.json before loading

1. **Compilation and Caching**:

- Automatic `.zwc` compilation for all modules via `zcompare()` function
- Module compilation happens during load for faster subsequentStartup
- Completion dump caching with timestamp-based invalidation
- Guard mechanisms to prevent double-loading of modules

### 4. Template System

Uses Go templates for environment-specific configuration:

- `{{ .business_use }}` - Business vs personal environment detection
- `{{ .chezmoi.os }}` - OS-specific configurations
- `{{ .chezmoi.homeDir }}` - Home directory path
- `{{ .chezmoi.arch }}` - Architecture detection (arm64 vs x86_64)
- XDG directory variables for proper path handling
- Homebrew prefix automatically set based on architecture
- Configuration defined in `.chezmoi.yaml.tmpl`

### 5. Hybrid Formatting System

**Architecture**: Combination of industry-standard tools for optimal file format support:

- **Prettier for Markdown**: Industry standard formatting for `.md` files via local pnpm installation
- **Custom zsh formatter**: Handles complex zsh syntax that prettier-plugin-sh couldn't parse
- **Mise task integration**: Unified interface via `mise run format` commands
- **Repository-local dependencies**: All formatting tools managed locally, not globally

**Configuration files**:

- `.prettierrc` - Prettier configuration (120 char width, preserve prose wrap)
- `package.json` - Local development dependencies and npm scripts
- `mise.toml` - Task runner definitions (NOT managed by chezmoi for local customization)

**Tool coordination**:

- prettier handles markdown formatting with consistent rules
- Custom script (`scripts/format_zsh.sh`) handles zsh files with syntax validation
- Both tools accessible via mise tasks and pnpm scripts for flexibility

### 6. Automated Setup

- `run_once_before_install-packages.sh.tmpl` - Package installation (Homebrew, etc.)
- `run_once_after_setup-zsh.sh.tmpl` - Zsh configuration and optimization
- Cross-platform package installation with CI skip capabilities
- Font installation: UDEVGothic35NFLG fonts are automatically installed to system font directory

## Important Configuration Details

### Core Architecture Rules

- **All file edits must be done via `chezmoi edit`** to maintain source synchronization
- **Module loading order is critical**: `platform.zsh` must be first, provides `is_exist_command`
- **PATH configuration in `.zshenv`**: Sourced early via `path.zsh` for consistency across all shell types
- **XDG compliance**: All configurations use XDG Base Directory variables

### Development Tools Integration

- **1Password CLI Integration**: `opr` function with environment file detection (`.env` local, `~/.env.1password` global)
- **1Password GitHub Integration**: Intentionally disabled due to vault configuration complexity (see `alias.zsh` comments)
- **mise (Runtime Manager)**: Conditional initialization based on shell context, XDG-compliant directories, manages Rust toolchain
- **Git Configuration**: Modular split (main, work settings, secrets) with environment-specific loading
- **Homebrew**: Analytics disabled, architecture-aware path configuration, Rust tools moved to cargo
- **Rust Tools**: Centralized management via cargo, defined in `packages/rust-tools.txt`

### Performance Monitoring Tools

- **`zprofiler`**: Full zsh profiling with `zprof` output
- **`zshtime`**: 10-iteration startup timing for performance benchmarking
- **Startup notifications**: Color-coded timing feedback (green <100ms, yellow <500ms, red >500ms)
- **`brewbundle`**: Automated Brewfile generation using chezmoi source directory

### Environment-Specific Features

- **Business/Personal switching**: `BUSINESS_USE` environment variable detection
- **Session-aware loading**: Different behavior in tmux/zellij vs standalone shells
- **Cross-platform compatibility**: macOS-specific optimizations with Linux fallbacks
- **CI/Docker compatibility**: Disabled security checks in containerized environments

### Enhanced Lazy Loading Configuration

**Environment Variables**:

- `LAZY_LOADING_ENABLED=1` - Enable/disable lazy loading system (default: enabled)
- `LAZY_LOADING_DEBUG=1` - Enable debug output for troubleshooting
- `TRACK_TOOL_USAGE=1` - Enable tool usage analytics for optimization hints
- `DOTS_DEBUG=1` - Enable general debug output for modules

**Project Context Detection** (automatic):

- Node.js: `package.json`, `pnpm-workspace.yaml`, `yarn.lock`, `pnpm-lock.yaml`
- Rust: `Cargo.toml`, `Cargo.lock`
- Python: `requirements.txt`, `pyproject.toml`, `setup.py`, `poetry.lock`
- Docker: `Dockerfile`, `docker-compose.yml`, `docker-compose.yaml`
- Kubernetes: `k8s/` directory, `kubectl.yaml`, `kustomization.yaml`, `$KUBECONFIG`
- Cloud: `.gcloudignore`, `.gcloud/`, `.aws/`, `$AWS_PROFILE`, `aws-cli.yaml`

**Tool Loading Behavior**:

- Container tools (docker, kubectl) only load in relevant project contexts
- Package managers (npm, yarn, pnpm) validate project context before loading
- Cloud tools (aws, gcloud) have expensive completions deferred until first use
- All tools track performance timing when debug mode is enabled

## Technical Implementation Patterns

### Module Development Guidelines

1. **Command Existence Checking**: Always use `is_exist_command` from `platform.zsh` before setting aliases or initializing tools
1. **PATH Management**: Use `path_prepend()` and `path_append()` functions instead of direct PATH manipulation
1. **Lazy Loading Pattern**:
   ```zsh
   _lazy_tool() {
     local args=("$@")
     unfunction _lazy_tool tool_name
     eval "$(tool_name init zsh)"
     tool_name "${args[@]}"
   }
   function tool_name() { _lazy_tool "$@" }
   ```
1. **Session Detection Pattern**:
   ```zsh
   if [[ -n "$TMUX" ]] || [[ -n "$ZELLIJ" && "$ZELLIJ" != "0" ]] || [[ "${SHLVL:-1}" -gt 2 ]]; then
     # Immediate initialization in sessions
   else
     # Lazy loading for main shell
   fi
   ```

### Performance Optimization Patterns

- **Zinit Turbo Mode**: Use `wait"N"` for deferred loading, higher numbers for less critical tools
- **Completion Timing**: Core completions at `wait"0"`, tool completions at `wait"2"`, heavy completions at `wait"3"`
- **Module Compilation**: All modules automatically compiled to `.zwc` via `zcompare()` function

## Local Configuration System

For machine-specific configurations that should not be tracked by git (work settings, private credentials, etc.):

### Configuration Locations (checked in order)

1. `~/.config/zsh/local.zsh` - XDG standard location (recommended)
1. `~/.zsh_local` - Traditional location
1. `~/.config/zsh/local/` - Directory for multiple local files

### Management Commands

- `local_config_init` - Create local configuration template
- `local_config_edit` - Edit local configuration (creates if missing)
- `local_config_show` - Display current local configurations

### Example Use Cases

```zsh

# Work-specific aliases

alias work-deploy='kubectl apply -f k8s/'
alias work-connect='ssh user@work.company.com'

# Environment variables

export WORK_API_KEY="secret-key"
export COMPANY_DOMAIN="company.com"

# Custom PATH additions

path_prepend "$HOME/work-tools/bin"

# Hostname-based conditional loading

if [[ "$(hostname)" == "work-laptop" ]]; then
    export BUSINESS_USE=1
    git config --global user.email "work@company.com"
fi
```

### Security Notes

- Local configuration files are automatically ignored by git
- Safe for sensitive information (API keys, work credentials)
- Loaded after all main modules for override capability
- **Cache Management**: XDG-compliant cache directories with timestamp-based invalidation

### Debugging and Maintenance

- **Module Debugging**: Set `DOTS_DEBUG=1` for additional debug output
- **Performance Profiling**: Use `ZPROFILER=1 zsh` or `zprofiler` function for detailed startup analysis
- **PATH Debugging**: Use `path_show`, `path_clean`, and `path_check` functions for PATH troubleshooting
- **Completion Debugging**: Check `$XDG_CACHE_HOME/zsh/zcompdump` for completion cache issues

## Performance Achievement Summary

The repository has achieved exceptional performance improvements through systematic optimization:

### Performance Metrics

- **Startup Time Reduction**: 92% improvement (600ms → 40-50ms)
- **Function Availability**: 100% - all critical functions operational (zprofiler, brewbundle, opr, lazy-stats)
- **Module Loading**: Sub-10ms module system initialization
- **Lazy Loading Overhead**: <5ms additional startup cost
- **Test Coverage**: 83+ tests across comprehensive and specialized test suites

### Key Achievements

1. **Complete Functionality Restoration**: Successfully restored all missing functions while maintaining performance gains
2. **Advanced Testing Infrastructure**: Implemented multi-tiered testing strategy with 71+ comprehensive tests and 12 specialized lazy loading tests
3. **Enhanced Module Architecture**: Deployed sophisticated dependency resolution system with metadata management
4. **Context-Aware Optimization**: Intelligent tool loading based on project type detection (Node.js, Docker, Rust, Kubernetes)
5. **Stability Improvements**: Fixed critical issues including Ctrl+R crashes and module integration problems

## Comprehensive Testing Infrastructure

### Test Suites Overview

**Comprehensive Test Suite** (`mise run test`):

- 71+ individual tests across 13 categories
- Syntax validation for all zsh modules
- Function availability verification
- Performance optimization validation
- Integration testing with real module loading
- Color-coded output with timing information

**Specialized Lazy Loading Tests** (`mise run test-lazy`):

- 12 focused tests for lazy loading system
- Project context detection validation (Node.js, Rust, Docker, Kubernetes)
- Performance regression testing (<200ms context detection)
- Wrapper function creation verification
- Module integration testing

**Test Categories Covered**:

- Core Dependencies (zsh, git, chezmoi, mise)
- Directory Structure Validation
- Module Syntax Validation (all modules)
- Configuration File Verification
- Module System Integration
- Lazy Loading System Testing
- Key Function Availability
- Performance Optimization Verification
- Helper Scripts Validation
- Documentation Completeness
- Chezmoi Integration Testing

## Recent Architectural Improvements

### Completion System Overhaul

- **Eliminated duplicate compinit calls**: Coordination between `core.zsh` and zinit to prevent multiple initialization
- **Function existence checking**: Proper zsh pattern `(( $+functions[function_name] ))` for reliable detection
- **Timing coordination**: Lazy-loaded tools (mise, atuin) have completions delayed to `wait"3"` to ensure proper initialization order
- **Error resilience**: Fallback completion loading when tools are not available

### PATH Management Refactoring

- **Centralized in `.zshenv`**: PATH configuration moved to early loading for consistency across all shell contexts
- **Environment variable standardization**: Added `GOBIN`, `PNPM_HOME` for proper tool path configuration
- **Duplicate prevention**: Safe prepend/append functions prevent PATH pollution

### Startup Optimization

- **Lazy command-not-found handler**: Homebrew handler only loads when needed, reducing startup overhead
- **Module organization**: Clear separation of concerns with unused modules (`logging.zsh`, `strings.zsh`) documented but not auto-loaded
- **Error handling patterns**: Consistent error checking and graceful fallbacks throughout

### Tool Integration Fixes

- **brewbundle function**: Fixed to use chezmoi source directory instead of global Brewfile location
- **1Password integration**: Temporarily disabled with clear re-enablement instructions due to vault configuration complexity
- **Cross-platform date handling**: macOS compatibility for timestamp generation in performance monitoring
- **Atuin Integration**: Moved from lazy loading to immediate initialization to prevent Ctrl+R crashes and binding conflicts
- **Local Configuration System**: Fixed math expression errors in local config management functions
- **Test Suite Integration**: Eliminated package.json dependency tests (development dependencies not tracked in dotfiles)

### Current Development Status

**Branch**: `optimize-performance` - Major architectural improvements completed
**Status**: All performance targets achieved with 100% functionality restored
**Key Metrics**:

- all comprehensive tests passing
- all lazy loading tests passing
- Startup time: 40-50ms (target: <100ms)
- All critical functions operational

**Ready for Production**: The performance optimization work has successfully achieved its goals. The branch demonstrates stable, high-performance zsh configuration suitable for daily use across development environments.
