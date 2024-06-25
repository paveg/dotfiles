alias vi="nvim"
alias vim="nvim"

# These are for zsh modules editing
alias zmod="nvim $ZMOD_PATH"

is_exist_command eza && {
  alias ls="eza"
  alias ll="eza -l"
  alias la="eza -la"
  alias lt="eza -T"
  alias l.="eza -d .*"
}

is_exist_command bat && {
  alias cat="bat -p"
}

is_exist_command fd && {
  alias find="fd"
}

# Lazygit
alias lg="lazygit"

# Kubernetes
alias k="kubectl"

# Ruby & Ruby on Rails
alias bi="bundle install"
alias be="bundle exec"
alias rc="bundle exec rails c"

# Git
alias ga="git add"
alias gb="git branch"
alias gc="git commit"
alias gco="git checkout"
alias gcb="git checkout -b"
alias gd="git diff"
alias gf="git fetch"
alias gp="git pull"
alias gr="git reset"
alias grb="git rebase"
alias gs="git status"
alias rub="_remove_unnecessary_branches"

# Utilities
alias rm="rm -i"
alias cp="cp -i"
alias mv="mv -i"
alias mkdir="mkdir -p"

