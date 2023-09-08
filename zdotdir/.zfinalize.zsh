IsExistCmd() { command -v "$1" > /dev/null 2>&1; }

IsExistCmd starship && eval "$(starship init zsh)" || echo "Not found starship: You can install it as curl -sS https://starship.rs/install.sh | sh"

typeset -U PATH fpath
