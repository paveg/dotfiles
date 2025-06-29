# Linux Package Lists

This directory contains package lists for different Linux distributions.

## Files

- `apt.txt` - Ubuntu/Debian packages (using apt)
- `dnf.txt` - Fedora/RHEL packages (using dnf)
- `pacman.txt` - Arch Linux packages (using pacman)
- `common.txt` - Documentation of common packages across distributions

## Usage

These files are automatically used by the installation script based on the detected package manager.

The installation script will:
1. Detect the available package manager
1. Install packages from the appropriate list
1. Handle distribution-specific package naming differences

## Package Categories

- **Core Development**: git, curl, wget, build tools
- **Shell Tools**: zsh, tmux, modern CLI replacements
- **Text Processing**: ripgrep, fd, fzf, bat, jq
- **Editor**: neovim
- **Monitoring**: htop

## Tools Installed via Dedicated Scripts

Some tools require special installation methods on Linux:

- **neovim**: Latest version via AppImage/binary (script: `install-neovim-latest.sh`)
- **Linux tools**: gh, mise, ghq, delta, lazygit (script: `install-linux-tools.sh`)
- Can install all at once: `./scripts/install-linux-tools.sh`
- Or specific tools: `./scripts/install-linux-tools.sh gh mise ghq`
- **atuin**: Shell history sync tool (installed via setup script)
- **Rust tools**: Various CLI tools via cargo (script: `install-rust-tools.sh`)
