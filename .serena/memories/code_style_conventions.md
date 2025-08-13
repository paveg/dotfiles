# Code Style and Conventions

## Zsh Module Style

- **Header format**: Consistent header blocks with module description and function lists
- **Function documentation**: Brief inline comments above functions
- **Module metadata**: Use `declare_module` for dependency tracking and metadata
- **Naming**: snake_case for functions, UPPER_CASE for environment variables
- **Error handling**: Use `set -euo pipefail` in bash scripts, proper return codes in zsh

## Module Architecture Patterns

- **Command existence checking**: Always use `is_exist_command` before setting aliases/initializing tools
- **PATH management**: Use `path_prepend()` and `path_append()` instead of direct manipulation
- **Lazy loading pattern**:
  ```zsh
  _lazy_tool() {
    local args=("$@")
    unfunction _lazy_tool tool_name
    eval "$(tool_name init zsh)"
    tool_name "${args[@]}"
  }
  function tool_name() { _lazy_tool "$@" }
  ```
- **Session detection**:
  ```zsh
  if [[ -n "$TMUX" ]] || [[ -n "$ZELLIJ" && "$ZELLIJ" != "0" ]] || [[ "${SHLVL:-1}" -gt 2 ]]; then
    # Immediate initialization in sessions
  else
    # Lazy loading for main shell
  fi
  ```

## File Organization

- **Core modules**: Essential functionality in `dot_config/zsh/modules/core/`
- **Tools**: Tool-specific modules in `dot_config/zsh/modules/tools/`
- **Config**: Basic configuration in `dot_config/zsh/modules/config/`
- **Loading order critical**: platform.zsh → core.zsh → others

## Template Conventions

- **Go templates**: Use `{{ .variable }}` syntax for chezmoi templates
- **Environment detection**: `{{ .business_use }}` for work/personal configs
- **XDG compliance**: Always use XDG variables for paths
- **Cross-platform**: `{{ .chezmoi.os }}` and `{{ .chezmoi.arch }}` for platform-specific code

## Performance Guidelines

- **Zinit turbo mode**: Use `wait"N"` for deferred loading
- **Completion timing**: Core at `wait"0"`, tools at `wait"2"`, heavy at `wait"3"`
- **Module compilation**: All modules auto-compiled to `.zwc` via `zcompare()`
- **Lazy loading**: Use project context detection for intelligent tool loading

## Testing Conventions

- **Bash scripts**: Use proper bash shebang, set strict mode
- **Color output**: Consistent color scheme (RED, GREEN, YELLOW, BLUE, CYAN)
- **Test structure**: Print headers, track pass/fail counters, provide timing info
- **Validation**: Syntax checking, function availability, performance benchmarks
