# Task Completion Checklist

## When a Task is Completed

### 1. Code Quality Checks

```bash
# ALWAYS run these after making changes:
mise run format                   # Format all files (required)
mise run format-check             # Verify formatting (optional verification)
```

### 2. Testing (Required for Module/Function Changes)

```bash
# For zsh module changes:
mise run test                     # Comprehensive test suite (71+ tests)
mise run test-lazy                # If lazy loading related (12 tests)

# For performance-critical changes:
mise run benchmark                # Benchmark startup time

# Quick validation:
mise run test-quick               # Fast module loading test
```

### 3. Chezmoi Operations

```bash
# After editing files, apply changes:
chezmoi apply                     # Apply to target files
chezmoi status                    # Verify no unexpected changes

# If adding new files:
chezmoi add <new-file>           # Add to chezmoi management
```

### 4. Environment-Specific Validation

```bash
# Test both environments if changes affect templating:
chezmoi apply                     # Personal environment
BUSINESS_USE=1 chezmoi apply      # Business environment
```

### 5. Performance Validation (for zsh changes)

```bash
# Ensure startup performance maintained:
zprofiler                        # Check for performance regressions
zshtime                          # Measure startup time (target: <100ms)

# If lazy loading changes:
lazy-stats                       # Check lazy loading effectiveness
```

### 6. Documentation Updates

- Update `CLAUDE.md` if architectural changes made
- Update relevant `docs/` files if significant feature changes
- Update module headers if function signatures changed

## Never Do These Without User Request

- **DO NOT commit changes** unless explicitly asked
- **DO NOT create new documentation files** unless requested
- **DO NOT push to remote** unless explicitly requested

## Before Committing (if requested)

```bash
git status                       # Review changes
git diff                         # Review specific changes
# Ensure all tests pass and formatting is correct before committing
```

## Emergency Recovery

If something breaks:

```bash
chezmoi source-path <broken-file> # Find source file
chezmoi edit <broken-file>        # Edit source
chezmoi apply                     # Re-apply
```
