# agkozak/zsh-z
alias j="z"

# Editor
alias vim="nvim"
alias vi="nvim"

# Git / hub https://github.com/mislav/hub
is_exist_command hub && eval "$(hub alias -s)"
alias g="hub"
alias ga="git add"
alias gs="git status"
alias gl="git log --oneline"
alias gc="git commit"
alias gp="git pull"
alias gb="git branch"
alias gd="git diff"
alias gr="git reset"
alias grb="git rebase"
alias gco="git checkout"
alias gcb="git checkout -b"
alias gpu="git push"
alias gsu="git submodule update --remote --recursive --recommend-shallow --depth 1 -f"

# ls / eza https://github.com/eza-community/eza
is_exist_command eza && alias ls="eza"
alias ll="ls -l"
alias la="ls -a"

# cat / bat https://github.com/sharkdp/bat
is_exist_command bat && alias cat="bat -p"

# rg https://github.com/BurntSushi/ripgrep
alias rg="rg --hidden"

# fd
alias find="fd"

# [Disabled] thefuck https://github.com/nvbn/thefuck
# is_exist_command thefuck && eval $(thefuck --alias)

# saml2aws
alias saml="saml2aws login --force --skip-prompt"
alias samlp="saml2aws login --force --skip-prompt --session-duration 3600"

# Ruby on Rails
alias be="bundle exec"
alias bi="bundle install -j4"
alias rr="bundle exec rails routes"
