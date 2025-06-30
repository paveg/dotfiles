#!/usr/bin/env zsh
# ============================================================================
# Command Aliases and Shortcuts
#
# This file defines command aliases and shortcuts to improve productivity.
# All aliases check for command existence before setting to avoid errors.
#
# Categories:
# - Editor shortcuts (vi, vim -> nvim)
# - File operations (ls, cat, grep replacements with modern tools)
# - Git shortcuts
# - Development tools
# - System utilities
# ============================================================================

# Module metadata declaration
declare_module "alias" \
  "depends:platform" \
  "category:utils" \
  "description:Command aliases and shortcuts for productivity" \
  "provides:vi,vim,zmod,ls,ll,la,lt,cat,find,lg,k,bi,be,rc,ga,gb,gc,gco,gcb,gd,gf,gp,gr,grb,gs,rub,rm,cp,mv,mkdir" \
  "external:nvim,eza,bat,fd,gh,lazygit,op" \
  "optional:op,gh"

alias vi="nvim"
alias vim="nvim"

# These are for zsh modules editing
alias zmod="nvim $ZMODDIR"

# Check if is_exist_command is available, define fallback if not
if ! command -v is_exist_command >/dev/null 2>&1; then
  is_exist_command() { command -v "$1" >/dev/null 2>&1; }
fi

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

# 1Password gh integration - disabled due to vault configuration issues
# To re-enable: run 'op plugin init gh' and uncomment below
# is_exist_command op && is_exist_command gh && {
#   alias gh="op plugin run -- gh"
# }

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

