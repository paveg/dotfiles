# Package Lists

This directory contains package lists for different Linux distributions to help install the required dependencies for the dotfiles.

## Usage

### Ubuntu/Debian
```bash
cat packages/apt.txt | xargs sudo apt install -y
```

### Fedora/RHEL
```bash
cat packages/dnf.txt | xargs sudo dnf install -y
```

## Notes

- Some modern CLI tools like `eza`, `bat`, `fd`, `ripgrep`, `delta`, `starship`, `lazygit` may not be available in default repositories and might need to be installed via:
  - Cargo: `cargo install <tool>`
  - Binary releases from GitHub
  - Third-party repositories (e.g., `cargo` via rustup, `mise` for runtime management)

- For `mise` (modern runtime manager), install from: https://mise.jdx.dev/
- For `gh` (GitHub CLI), install from: https://cli.github.com/
- For `lazygit`, install from: https://github.com/jesseduffield/lazygit

## Alternative Installation Methods

If packages are not available in your distribution's repositories:

1. **Use mise for runtime management**: `mise use -g go@latest node@latest python@latest`
2. **Use cargo for Rust tools**: `cargo install eza bat fd-find ripgrep git-delta starship`
3. **Download binaries directly** from GitHub releases for tools like `gh`, `lazygit`