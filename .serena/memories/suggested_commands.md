# Essential Commands for Development

## Chezmoi Operations (Primary Interface)

```bash
# Status and management
chezmoi status                    # Check status of managed files
chezmoi apply                     # Apply changes from source to target
chezmoi diff                      # Show differences between source and target
chezmoi edit <file>               # Edit source file (ALWAYS use this for editing)
chezmoi source-path <file>        # Find source path for target file
chezmoi managed                   # List all managed files

# Installation
chezmoi init --apply paveg        # Fresh install
BUSINESS_USE=1 chezmoi apply      # Apply business/work configurations
```

## Testing and Validation

```bash
mise run test                     # Run comprehensive test suite (71+ tests)
mise run test-lazy                # Test lazy loading system (12 tests)
mise run test-quick               # Quick module loading test
mise run benchmark                # Benchmark zsh startup time (5 runs)
./tests/test_runner.sh            # Legacy test suite
```

## Formatting and Code Quality

```bash
mise run format                   # Format all files (MD + zsh)
mise run format-check             # Check formatting without changes
mise run format-md                # Format only markdown with prettier
mise run format-zsh               # Format only zsh files with custom formatter
pnpm run format:md                # Alternative: format markdown
```

## Performance Monitoring

```bash
zprofiler                         # Full zsh profiling with zprof output
zshtime                          # 10-iteration startup timing benchmark
lazy-stats                       # Show lazy loading statistics
```

## Package Management

```bash
# Homebrew
brewbundle                       # Update current Brewfile
brew bundle                      # Install packages from Brewfile
brew bundle --file=homebrew/Brewfile.work  # Install work-specific packages

# Rust tools
./scripts/install_rust_tools.sh  # Install/update Rust tools (optimized)
mise install rust@stable         # Manage Rust version
```

## Development Tools

```bash
# Local development
pnpm install                     # Install dev dependencies
mise install                     # Install mise-managed tools

# Neovim
:Lazy update                     # Update plugins
:AstroUpdate                     # Update AstroNvim
```

## System Utilities (Darwin-specific)

- Standard Unix commands available: `ls`, `cd`, `grep`, `find`
- Use `gls`, `ggrep` etc. for GNU versions (if installed via Homebrew)
- `pbcopy`/`pbpaste` for clipboard operations
- `open` for opening files/URLs
