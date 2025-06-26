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

- `brewbundle` - Update current Brewfile (respects BUSINESS_USE environment)
- `brewbundle_personal` - Update personal Brewfile specifically
- `brewbundle_work` - Update work Brewfile specifically
- `brewbundle_diff` - Show differences between personal and work Brewfiles
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

Located in `dot_config/zsh/modules/`, featuring sophisticated lazy loading and optimization:

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

1. **Smart Tool Initialization**:
- Context-aware lazy loading: immediate in sessions (tmux/zellij), lazy in main shell
- Session detection via `$TMUX`, `$ZELLIJ`, and `$SHLVL` variables
- Tool-specific lazy wrappers that self-destruct after first use
- Startup time measurement with color-coded performance feedback

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
- XDG directory variables for proper path handling

### 5. Automated Setup

- `run_once_before_install-packages.sh.tmpl` - Package installation (Homebrew, etc.)
- `run_once_after_setup-zsh.sh.tmpl` - Zsh configuration and optimization
- Cross-platform package installation with CI skip capabilities

## Important Configuration Details

### Core Architecture Rules

- **All file edits must be done via `chezmoi edit`** to maintain source synchronization
- **Module loading order is critical**: `platform.zsh` must be first, provides `is_exist_command`
- **PATH configuration in `.zshenv`**: Sourced early via `path.zsh` for consistency across all shell types
- **XDG compliance**: All configurations use XDG Base Directory variables

### Development Tools Integration

- **1Password CLI Integration**: `opr` function with environment file detection (`.env` local, `~/.env.1password` global)
- **1Password GitHub Integration**: Intentionally disabled due to vault configuration complexity (see `alias.zsh` comments)
- **mise (Runtime Manager)**: Conditional initialization based on shell context, XDG-compliant directories
- **Git Configuration**: Modular split (main, work settings, secrets) with environment-specific loading
- **Homebrew**: Analytics disabled, architecture-aware path configuration

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
