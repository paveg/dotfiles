# Task Completion Guidelines

## When a Task is Completed

After completing any development task in this dotfiles repository, always run these commands in order:

### 1. Code Quality Checks

```bash
mise run format                   # Format all files (markdown + zsh)
mise run test                     # Run comprehensive test suite
```

### 2. Chezmoi Operations (if config files were modified)

```bash
chezmoi status                    # Check what will be applied
chezmoi apply                     # Apply changes to target files
```

### 3. Environment-Specific Testing (if applicable)

```bash
# Test personal environment
chezmoi apply

# Test business environment
BUSINESS_USE=1 chezmoi apply
```

### 4. Performance Validation (for zsh changes)

```bash
mise run benchmark               # Benchmark startup time
zprofiler                       # Profile if performance issues
```

### 5. Specific Validation Commands

**For Alacritty changes:**

```bash
alacritty --config-file ~/.config/alacritty/alacritty.toml  # Test config
```

**For Zsh module changes:**

```bash
mise run test-lazy              # Test lazy loading system
zsh -i -c exit                 # Test interactive shell startup
```

**For Template changes:**

```bash
chezmoi execute-template < file.tmpl  # Validate template syntax
```

## Never Skip These Steps

- ALWAYS format code before committing
- ALWAYS run tests after making changes
- ALWAYS use `chezmoi apply` after editing source files
- ALWAYS validate environment-specific configurations work

## Git Workflow (if requested)

1. Only commit after all validation passes
2. Use descriptive commit messages
3. Follow conventional commit format if applicable
4. Push only if explicitly requested by user
