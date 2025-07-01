# Test Organization

## Overview

The dotfiles repository includes comprehensive testing to ensure reliability and performance. Tests are organized into multiple levels and can be run via `mise` tasks.

## Available Test Commands

### Via mise

```bash
# Run comprehensive test suite (recommended)
mise run test

# Test lazy loading system specifically
mise run test-lazy

# Quick module loading test
mise run test-quick

# Benchmark startup performance
mise run benchmark

# Check formatting
mise run format-check
```

### Direct Script Execution

```bash
# Comprehensive test suite
./scripts/test-comprehensive.sh

# Lazy loading specific tests
./scripts/test-lazy-loading.sh

# Legacy test runner
./tests/test_runner.sh
```

## Test Suite Organization

### 1. Comprehensive Test Suite (`mise run test`)

The main test suite covers all aspects of the dotfiles system:

1. **Core Dependencies**: Zsh, Git, Chezmoi, Mise availability
2. **Directory Structure**: All module directories exist
3. **Module Syntax Validation**: All `.zsh` files have valid syntax
4. **Configuration Files**: Templates and config files exist
5. **Module System**: Metadata and loader system functionality
6. **Lazy Loading System**: Context detection and lazy loading
7. **Key Functions**: zprofiler, brewbundle, etc. are defined
8. **Performance Optimizations**: Plugin timing and caching
9. **Aliases and Commands**: Common aliases are defined
10. **Helper Scripts**: All scripts exist and are executable
11. **Documentation**: All docs exist
12. **Integration Tests**: Full system loads without errors
13. **Chezmoi Integration**: Templates use correct syntax

### 2. Lazy Loading Tests (`mise run test-lazy`)

Focused tests for the lazy loading system:

- Project context detection (Node.js, Docker, Rust, etc.)
- Performance timing functions
- Enhanced tool loading (mise, atuin)
- Plugin timing optimization
- Module loading performance

### 3. Quick Tests (`mise run test-quick`)

Rapid validation that core modules load:

- Platform detection
- Core module loading
- Lazy loading functions availability
- Project context detection

### 4. Performance Benchmarking (`mise run benchmark`)

- Runs 5 iterations of shell startup
- Calculates average startup time
- Helps track performance regressions

## Test Output

Tests provide color-coded output:

- 🟢 **PASSED**: Test succeeded
- 🔴 **FAILED**: Test failed
- 🟡 **SKIPPED**: Test was skipped with reason

Each test shows:

- Test name (left-aligned, 60 chars)
- Result status with color
- Execution time (for passed tests)

## Test Categories

### Syntax Tests

Validate that all zsh modules have correct syntax using `zsh -n`.

### Function Tests

Verify that expected functions are defined in their respective modules.

### Integration Tests

Ensure modules can load together without conflicts.

### Performance Tests

Check that optimizations are in place (wait times, caching, etc.).

### Documentation Tests

Verify all documentation files exist.

## Writing New Tests

To add new tests, edit the appropriate test script:

1. **For general tests**: Add to `scripts/test-comprehensive.sh`
2. **For lazy loading**: Add to `scripts/test-lazy-loading.sh`
3. **For quick checks**: Update the `test-quick` task in `mise.toml`

### Test Function Usage

```bash
# Run a test
run_test "Test name" "test command"

# Skip a test
skip_test "Test name" "reason for skipping"

# Print a section header
print_section "Section Name"
```

## Continuous Integration

While no CI is currently configured, the test suite is designed to be CI-ready. All tests exit with:

- `0` on success (all tests passed)
- `1` on failure (one or more tests failed)

## Performance Targets

Based on the optimization strategy:

- **Startup time**: < 100ms (internal), ~580ms (total process)
- **Module loading**: < 1 second for full init
- **Function availability**: 100% in interactive shells

## Debugging Failed Tests

1. Run the specific failing test command manually
2. Add `set -x` to the test script for verbose output
3. Check module dependencies with `DOTS_DEBUG=1`
4. Use `zprofiler` to identify performance issues

## Next Steps

After running tests:

1. If tests pass: Run `mise run benchmark` for performance check
2. If tests fail: Check specific failures and debug
3. For formatting: Run `mise run format` to auto-fix
4. For lazy loading issues: Run `mise run test-lazy` for detailed checks
