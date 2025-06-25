# Dotfiles with Chezmoi

This repository uses [chezmoi](https://www.chezmoi.io/) for cross-platform dotfile management with templating support.

## Features

- **Cross-platform**: Supports macOS, Linux, and Windows WSL
- **Templating**: OS-specific configurations using Go templates
- **XDG compliance**: Follows XDG Base Directory Specification
- **Performance optimized**: Lazy loading and compiled zsh files
- **Business/Personal modes**: Different configurations via `BUSINESS_USE` environment variable

## Quick Start

### Installation

```bash
# Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)"

# Initialize with this repository
chezmoi init https://github.com/paveg/dotfiles

# Preview changes
chezmoi diff

# Apply dotfiles
chezmoi apply
```

### Business/Work Setup

```bash
# Set business mode before applying
export BUSINESS_USE=1
chezmoi apply
```

## Structure

```
.
├── .chezmoi.yaml.tmpl              # Chezmoi configuration template
├── .chezmoiignore                  # Files to ignore
├── dot_zshenv.tmpl                 # ~/.zshenv template
├── .config/
│   ├── zsh/
│   │   ├── dot_zshrc.tmpl         # ~/.config/zsh/.zshrc template
│   │   ├── dot_zprofile.tmpl      # ~/.config/zsh/.zprofile template
│   │   └── modules/               # Zsh modules
│   ├── git/                       # Git configuration
│   ├── nvim/                      # Neovim configuration
│   ├── starship.toml              # Starship prompt config
│   └── ...                        # Other tool configs
├── homebrew/
│   ├── Brewfile                   # Personal packages
│   └── Brewfile.work              # Work packages
└── run_*                          # Installation scripts
```

## Templates

Chezmoi uses Go templates with the following variables:

- `.chezmoi.os`: Operating system (darwin, linux, windows)
- `.chezmoi.arch`: Architecture (amd64, arm64)
- `.business_use`: Business mode flag
- `.xdg_*`: XDG directory paths
- `.homebrew_prefix`: Homebrew installation path

### Example Template Usage

```yaml
{{- if eq .chezmoi.os "darwin" -}}
# macOS specific configuration
export HOMEBREW_PREFIX="{{ .homebrew_prefix }}"
{{- else if eq .chezmoi.os "linux" -}}
# Linux specific configuration
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
{{- end }}

{{- if .business_use }}
# Work-specific settings
export BUSINESS_USE=1
{{- end }}
```

## Commands

### Daily Usage

```bash
# Update dotfiles from repository
chezmoi update

# Edit a file and apply changes
chezmoi edit ~/.zshrc
chezmoi apply

# Add a new file to be managed
chezmoi add ~/.gitconfig

# Show what would change
chezmoi diff
```

### Development

```bash
# Re-run installation scripts
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply

# Execute template manually
chezmoi execute-template < .chezmoi.yaml.tmpl

# Debug template variables
chezmoi data
```

## Migration from install.sh

The previous `install.sh` approach has been replaced with chezmoi for better:

1. **Cross-platform support**: Templates handle OS differences automatically
2. **Maintenance**: No custom bash scripting required
3. **Testing**: Simpler CI/CD with `chezmoi diff` and `chezmoi apply --dry-run`
4. **State management**: Chezmoi tracks what's been applied

### Key Differences

| install.sh | chezmoi |
|------------|---------|
| Custom bash scripts | Standard tool with templates |
| Manual symlink management | Automatic file management |
| OS detection in bash | Template-based OS detection |
| Complex CI setup | Simple `chezmoi apply` testing |

## Troubleshooting

### Common Issues

1. **Template errors**: Use `chezmoi execute-template` to debug
2. **File conflicts**: Use `chezmoi merge` or `chezmoi diff` to resolve
3. **Permission issues**: Check file permissions in source directory
4. **Missing dependencies**: Run `brew bundle` to install packages

### Performance

- Zsh startup time optimized with lazy loading
- Use `ZPROFILER=1 zsh` to measure startup performance
- Compiled `.zwc` files for faster loading

## Contributing

1. Make changes to templates in the source directory
2. Test with `chezmoi diff` and `chezmoi apply --dry-run`
3. Verify cross-platform compatibility with CI tests
4. Update this README for any new features