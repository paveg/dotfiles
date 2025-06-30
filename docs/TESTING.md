# Module System Testing Guide

This guide shows how to test the new enhanced module system with dependency resolution.

## Quick Test Commands

### 1. Test Basic Functionality

```bash
# Test metadata system
zsh -c "
export XDG_CONFIG_HOME=\$(pwd)
export ZDOTDIR=\$XDG_CONFIG_HOME/dot_config/zsh
source dot_config/zsh/modules/core/metadata.zsh
echo 'Functions available:' \$(typeset -f | grep '^declare_module\|^is_module_loaded' | wc -l)
"

# Test dependency resolution
zsh -c "
export XDG_CONFIG_HOME=\$(pwd)
export ZDOTDIR=\$XDG_CONFIG_HOME/dot_config/zsh
source dot_config/zsh/modules/core/metadata.zsh
declare_module 'test_a' 'depends:test_b'
declare_module 'test_b' 'category:test'
get_load_order | grep test
"
```

### 2. Test Module Loading

```bash
# Test minimal loading
DOTS_ONLY_MODULES="platform,core" \
XDG_CONFIG_HOME=\$(pwd) \
ZDOTDIR=\$(pwd)/dot_config/zsh \
zsh -c "source dot_config/zsh/init.zsh; echo 'Platform loaded:' \$(type ostype)"

# Test full loading (without external dependencies)
DOTS_SKIP_MODULES="plugin" \
XDG_CONFIG_HOME=\$(pwd) \
ZDOTDIR=\$(pwd)/dot_config/zsh \
zsh -c "source dot_config/zsh/init.zsh; list_modules"
```

### 3. Test Migration (Dry Run)

```bash
# Test migration script without making changes
./scripts/migrate-modules.sh --dry-run

# Test documentation generation
./scripts/generate-module-docs.sh --output /tmp/test_docs.md --graph
```

## Advanced Testing

### Test Performance

```bash
# Benchmark loading times
for i in {1..3}; do
  time (DOTS_DEBUG=0 XDG_CONFIG_HOME=\$(pwd) ZDOTDIR=\$(pwd)/dot_config/zsh zsh -c "source dot_config/zsh/init.zsh" >/dev/null 2>&1)
done
```

### Test Dependency Resolution

```bash
# Test circular dependency detection
zsh -c "
export XDG_CONFIG_HOME=\$(pwd)
export ZDOTDIR=\$XDG_CONFIG_HOME/dot_config/zsh
source dot_config/zsh/modules/core/metadata.zsh
declare_module 'a' 'depends:b'
declare_module 'b' 'depends:c'
declare_module 'c' 'depends:a'
get_load_order 2>&1 || echo 'Circular dependency correctly detected'
"
```

### Test Module Management

```bash
# Test module commands
XDG_CONFIG_HOME=\$(pwd) ZDOTDIR=\$(pwd)/dot_config/zsh zsh -c "
source dot_config/zsh/init.zsh
echo '=== Module List ==='
list_modules
echo '=== Module Validation ==='
validate_modules
"
```

## Real Environment Testing

### 1. Test in User Environment

```bash
# CAREFUL: This affects your real zsh config
# Backup first!
cp ~/.config/zsh ~/.config/zsh.backup

# Apply changes
chezmoi apply

# Test new system
DOTS_DEBUG=1 zsh -l
```

### 2. Test Specific Scenarios

```bash
# Test with business environment
BUSINESS_USE=1 DOTS_DEBUG=1 zsh -l

# Test minimal loading
DOTS_ONLY_MODULES="platform,core,config" zsh -l

# Test without experimental modules
DOTS_SKIP_MODULES="logging,strings" zsh -l
```

## Test Checklist

- [ ] Metadata system loads without errors
- [ ] Module declarations work correctly
- [ ] Dependency resolution works (both valid and circular)
- [ ] Basic module loading (platform, core) works
- [ ] Module management commands available
- [ ] Performance is acceptable (< 500ms startup)
- [ ] Migration script runs without errors
- [ ] Documentation generation works
- [ ] Full system loads in real environment
- [ ] All existing functionality still works

## Common Issues

### 1. "command not found: declare_module"

**Cause**: Module trying to declare metadata before metadata system loaded  
**Fix**: Ensure metadata.zsh loads first in dependency chain

### 2. "zsh/parameter.so" errors

**Cause**: Zsh trying to load compiled modules from wrong path  
**Fix**: These are warnings and don't affect functionality

### 3. "read-only variable: status"

**Cause**: Variable name conflict in module system  
**Fix**: Use different variable names in modules

### 4. Functions not available after loading

**Cause**: Module source failed or wrong dependency order  
**Fix**: Check DOTS_DEBUG=1 output for loading errors

## Emergency Rollback

If something goes wrong:

```bash
# Restore original config
cp ~/.config/zsh.backup ~/.config/zsh

# Or reset chezmoi
chezmoi init --apply paveg

# Check what changed
chezmoi diff
```

## Success Criteria

The module system is working correctly when:

1. `DOTS_DEBUG=1 zsh -l` shows modules loading in dependency order
2. `list_modules` shows all modules with correct categories
3. `module-validate` passes without errors
4. Startup time is reasonable (< 1 second)
5. All existing aliases/functions still work
6. No error messages during normal shell usage
