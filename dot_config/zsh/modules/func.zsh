#!/usr/bin/env zsh
# ============================================================================
# Utility Functions
#
# This file contains custom utility functions for improved workflow.
#
# Functions:
# - _fzf_cd_ghq: Interactive repository navigation with fzf
# - opr: 1Password CLI integration for secret retrieval
# - rub: Git branch cleanup utility
# - Various other workflow helpers
# ============================================================================


_fzf_cd_ghq() {
  local root="$(ghq root)"
  local repo="$(ghq list | fzf --reverse --height=60% \
    --preview='
      repo_path="'$root'/{}"
      # Try README files first
      for readme in README.md README.rst README.txt README readme.md; do
        if [[ -f "$repo_path/$readme" ]]; then
          echo "📖 $readme"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          bat --color=always --style=grid --line-range :50 "$repo_path/$readme" 2>/dev/null || head -50 "$repo_path/$readme"
          exit
        fi
      done
      
      # Fallback when no README
      echo "📁 $(basename "$repo_path")"
      echo "📍 $repo_path"
      echo ""
      
      if [[ -d "$repo_path/.git" ]]; then
        echo "🔧 Git Repository"
        cd "$repo_path" 2>/dev/null && {
          echo ""
          echo "📊 Recent commits:"
          git log --oneline --color=always -8 2>/dev/null || echo "  No commits"
          echo ""
          echo "🌿 Branches:"
          git branch -a --color=always 2>/dev/null | head -8 || echo "  No branches"
        }
      else
        echo "📄 Contents:"
        ls -la "$repo_path" 2>/dev/null | head -10 || echo "  Cannot access"
      fi
    ' \
    --preview-window=right:50%)"
  local dir=$root/$repo
  if [[ -n $dir && $dir != $root/ ]]; then
    BUFFER="cd $dir"
    zle accept-line
  else
    zle reset-prompt
  fi
}

# This function is for 1password-cli
opr () {
    who=$(op whoami)
    if [[ $? != 0 ]]; then
        eval "$(op signin)"
    fi
    if [[ -f "$PWD/.env" ]]; then
        op run --env-file=$PWD/.env -- $@
    else
        op run --env-file=$HOME/.env.1password -- $@
    fi
}

zprofiler() {
  ZSHRC_PROFILE=1 zsh -i -c zprof
}

zshtime() {
  for i in $(seq 1 10); do time zsh -i -c exit >/dev/null; done
}

brewbundle() {
  local brewfile="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}/homebrew/Brewfile"
  if [[ ! -f "$brewfile" ]]; then
    echo "Error: Brewfile not found at $brewfile" >&2
    return 1
  fi
  brew bundle dump --verbose --force --cleanup --cask --formula --mas --tap --file="$brewfile"
  echo "Updated: $brewfile"
}

PROTECTED_BRANCHES='main|master|develop|staging'
_remove_unnecessary_branches() {
  git branch --merged | egrep -v "\*|${PROTECTED_BRANCHES}" | xargs git branch -d
}
