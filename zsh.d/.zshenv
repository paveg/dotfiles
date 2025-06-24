export SHELL=/bin/zsh
# ============================================================================
# PATH Configuration (Consolidated)
# ============================================================================
typeset -Ug path PATH

# Package manager configuration
export PNPM_HOME="$HOME/Library/pnpm"

# Construct PATH with essential development tools
path=(
  # Homebrew (highest priority for macOS)
  /opt/homebrew/bin(N-/)
  /opt/homebrew/sbin(N-/)

  # User-specific binaries (only if they exist)
  $HOME/bin(N-/)

  # Node.js package manager
  $PNPM_HOME(N-/)                 # PNPM

  # Development utilities
  $HOME/.console-ninja/.bin(N-/)  # Console Ninja

  # Keep existing system paths (mise will add language-specific paths)
  $path[@]
)

# Locales
export LANG=C
export LC_CTYPE=ja_JP.UTF-8

export REPO_NAME=dotfiles

# Repository management is following https://github.com/x-motemen/ghq
export GHQ_ROOT=$HOME/repos

# Default configurations
export DOTDIR=$GHQ_ROOT/github.com/paveg/$REPO_NAME
export XDG_CONFIG_HOME=$HOME/.config
export EDITOR=nvim

# zsh
export ZDOTDIR="$DOTDIR/zsh.d"
export ZMODDIR="$ZDOTDIR/modules"

# https://github.com/junegunn/fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS="--ansi --tiebreak=index --height 60% --layout=reverse --border --preview-window 'right:50%'"

# https://starship.rs/
export STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml

# Additional development tool configurations can be added here
