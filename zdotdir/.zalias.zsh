IsExistCmd() { command -v "$1" > /dev/null 2>&1; }

# agkozak/zsh-z
alias j="z"

# Git
alias ga="git add"
alias gs="git status"
alias gl="git log --oneline"
alias gc="git commit"
alias gp="git pull"
alias gb="git branch"
alias gd="git diff"
alias gco="git checkout"
alias gcb="git checkout -b"

# ls / eza https://github.com/eza-community/eza
IsExistCmd eza && alias ls="eza"

# cat / bat https://github.com/sharkdp/bat
IsExistCmd bat && alias cat="bat -p"

# rg https://github.com/BurntSushi/ripgrep
alias rg="rg --hidden"
