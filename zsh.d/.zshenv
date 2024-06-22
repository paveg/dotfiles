eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(mise activate zsh --shims)"

export REPO_NAME=dotfiles

# Repository management is following https://github.com/x-motemen/ghq
export GHQ_ROOT=$HOME/repos

# Default configurations
export DOT_PATH=$GHQ_ROOT/github.com/paveg/$REPO_NAME
export XDG_CONFIG_HOME=$HOME/.config

# zsh
export ZDOT_PATH="$DOT_PATH/zsh.d"
export ZMOD_PATH="$ZDOT_PATH/modules"

# https://github.com/junegunn/fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS="--ansi --tiebreak=index --height 60% --layout=reverse --border --preview-window 'right:50%'"

# https://starship.rs/
export STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml
