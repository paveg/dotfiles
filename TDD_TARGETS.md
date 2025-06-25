# TDD Target List for macOS dotfiles

## 🎯 Priority 1: Core Shell Functionality (Week 1)

### Test-First Implementation Targets

#### 1. **Shell Startup**
- [ ] Test: Zsh starts without errors
- [ ] Test: Startup time < 150ms
- [ ] Test: No command not found errors
- [ ] Implementation: Basic .zshrc that passes tests

#### 2. **Environment Variables**
- [ ] Test: `$DOTDIR` is set correctly
- [ ] Test: `$XDG_CONFIG_HOME` is set
- [ ] Test: `$PATH` contains essential directories
- [ ] Implementation: .zshenv with proper exports

#### 3. **Module Loading System**
- [ ] Test: Core module loads successfully
- [ ] Test: Load function is available
- [ ] Test: Module compilation works
- [ ] Implementation: Minimal core.zsh module

## 🎯 Priority 2: Essential Tools (Week 2)

### Package Manager Detection
- [ ] Test: Homebrew is detected on macOS
- [ ] Test: Essential formula can be installed
- [ ] Test: Cask applications can be installed
- [ ] Implementation: Package detection utilities

### Tool Availability Tests
- [ ] Test: Git is available and configured
- [ ] Test: Essential CLI tools (fd, rg, bat, eza)
- [ ] Test: Development tools (mise, nvim)
- [ ] Implementation: Tool installation automation

## 🎯 Priority 3: Configuration Loading (Week 3)

### Git Configuration
- [ ] Test: Git config files are linked correctly
- [ ] Test: Git aliases work
- [ ] Test: Git credentials are configured
- [ ] Implementation: Git config installation

### Zsh Modules
- [ ] Test: Platform detection works (is_osx)
- [ ] Test: Logging functions available
- [ ] Test: Aliases are loaded
- [ ] Implementation: Module system

## 🎯 Priority 4: Plugin System (Week 4)

### Zinit Setup
- [ ] Test: Zinit installs correctly
- [ ] Test: Plugins load without errors
- [ ] Test: Deferred loading works
- [ ] Implementation: Plugin configuration

### Essential Plugins
- [ ] Test: Syntax highlighting works
- [ ] Test: Autosuggestions work
- [ ] Test: Completions work
- [ ] Implementation: Plugin list

## 🎯 Priority 5: Performance & Integration (Week 5)

### Performance Tests
- [ ] Test: Shell startup benchmark
- [ ] Test: Command execution speed
- [ ] Test: Memory usage baseline
- [ ] Implementation: Performance optimizations

### Integration Tests
- [ ] Test: Fresh install scenario
- [ ] Test: Update scenario
- [ ] Test: Minimal install scenario
- [ ] Implementation: Install script improvements

## 📝 Test Implementation Order

### Phase 1: Minimal Viable Tests (Day 1-3)
```yaml
# .github/workflows/test-minimal.yml
- Shell starts
- Basic syntax validation
- Core files exist
```

### Phase 2: Functional Tests (Day 4-7)
```yaml
# .github/workflows/test-functional.yml
- Environment variables set
- Functions available
- Commands work
```

### Phase 3: Integration Tests (Week 2)
```yaml
# .github/workflows/test-integration.yml
- Full installation
- Tool availability
- Cross-dependency checks
```

## 🔧 Test File Structure

```
tests/
├── unit/
│   ├── test_shell_startup.sh
│   ├── test_environment.sh
│   ├── test_modules.sh
│   └── test_functions.sh
├── integration/
│   ├── test_fresh_install.sh
│   ├── test_tool_availability.sh
│   └── test_performance.sh
├── fixtures/
│   ├── minimal_zshrc
│   └── expected_outputs/
└── test_runner.sh
```

## 📊 Success Metrics

### Must Pass (Before Any Implementation)
1. Shell starts without errors
2. Basic commands available
3. No syntax errors
4. Core structure intact

### Should Pass (After Implementation)
1. Performance benchmarks met
2. All tools available
3. Plugins functional
4. Cross-platform ready

### Nice to Have
1. Automated dependency updates
2. Self-healing configurations
3. Performance monitoring
4. Usage analytics

## 🚀 Next Steps

1. **Create test branch**: `git checkout -b test-driven-development`
2. **Run minimal test**: `./tests/test_runner.sh`
3. **Fix failures**: Implement only what's needed to pass
4. **Add new test**: Write next failing test
5. **Repeat**: Red → Green → Refactor cycle