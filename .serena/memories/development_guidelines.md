# Development Guidelines and Patterns

## Critical Architecture Rules

### 1. File Editing Protocol

- **ALWAYS use `chezmoi edit <file>`** to edit any managed file
- **NEVER directly edit files in `~/.config/`** - they will be overwritten
- **Source directory**: `/Users/ryota/.local/share/chezmoi/` contains the source files
- **Target directory**: User's home directory contains the generated files

### 2. Module Loading Dependencies

- **`platform.zsh` MUST be loaded first** - provides `is_exist_command` used everywhere
- **Critical loading order**: platform → core → path → config → others
- **Module metadata system**: Use `declare_module` for proper dependency tracking
- **Circular dependency detection**: Built into the advanced loader system

### 3. Performance Requirements

- **Startup time target**: <100ms (currently achieving 40-50ms)
- **Lazy loading mandatory**: Tools only load when needed or in relevant project contexts
- **Zinit turbo mode**: Use appropriate wait times (0/2/3) for deferred loading
- **Module compilation**: All modules auto-compile to `.zwc` for faster loading

## Design Patterns

### 1. Command Existence Pattern

```zsh
# ALWAYS check before using commands
if is_exist_command "tool_name"; then
    alias shortcut="tool_name --option"
    # Initialize tool
fi
```

### 2. PATH Management Pattern

```zsh
# Use helper functions to prevent duplicates
path_prepend "/new/path"
path_append "/fallback/path"

# Never directly modify PATH
# PATH="/new/path:$PATH"  # ❌ Don't do this
```

### 3. Environment-Aware Configuration

```zsh
# Template pattern for dual environments
{{- if .business_use }}
# Business-specific configuration
{{- else }}
# Personal configuration
{{- end }}
```

### 4. Session-Aware Loading

```zsh
# Different behavior for nested vs main shells
if [[ -n "$TMUX" ]] || [[ -n "$ZELLIJ" && "$ZELLIJ" != "0" ]] || [[ "${SHLVL:-1}" -gt 2 ]]; then
    # Immediate initialization in sessions/nested shells
    eval "$(tool init zsh)"
else
    # Lazy loading for main shell
    _lazy_tool() { ... }
fi
```

## Security and Best Practices

### 1. Secrets Management

- **Never commit secrets** to the repository
- **Use local.zsh** for machine-specific sensitive config
- **1Password integration**: Use `opr` function for secure environment loading
- **Local files ignored**: `local.zsh`, `.env.local`, etc. not tracked by git

### 2. Cross-Platform Compatibility

- **OS detection**: Use `ostype()`, `is_osx()`, `is_linux()` functions
- **Architecture awareness**: Handle Apple Silicon vs Intel differences
- **Tool availability**: Always check with `is_exist_command`
- **Fallback mechanisms**: Provide alternatives when tools unavailable

### 3. Error Handling

- **Bash scripts**: Use `set -euo pipefail` for strict error handling
- **Zsh functions**: Return proper exit codes, handle edge cases
- **Graceful degradation**: Continue working even if optional tools unavailable
- **Debug modes**: Support `DOTS_DEBUG=1` and `LAZY_LOADING_DEBUG=1`

## Testing Strategy

### 1. Multi-Tiered Testing

- **Comprehensive tests** (71+): Full system validation
- **Specialized tests** (12): Lazy loading focused
- **Performance benchmarks**: Startup time regression detection
- **Integration tests**: Real module loading with timing

### 2. Test Coverage Areas

- **Syntax validation**: All zsh modules for shell compatibility
- **Function availability**: Critical functions accessible after loading
- **Performance validation**: Startup time within targets
- **Cross-environment**: Both personal and business configurations
- **Dependency validation**: Module loading order and dependencies

### 3. Continuous Validation

- **Pre-commit hooks**: Formatting and basic syntax validation
- **CI-compatible**: Tests work in containerized environments
- **Local development**: Quick feedback via `mise run test-quick`
