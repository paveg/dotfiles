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

_ghq_preview() {
  local repo_path="$1"
  
  # Try to find and display README files
  for readme in README.md README.rst README.txt README readme.md readme.rst readme.txt readme; do
    if [[ -f "$repo_path/$readme" ]]; then
      echo "📖 $readme"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      bat --color=always --style=grid --line-range :50 "$repo_path/$readme" 2>/dev/null || cat "$repo_path/$readme" 2>/dev/null
      return 0
    fi
  done
  
  # Fallback: No README found
  echo "📁 Repository: $(basename "$repo_path")"
  echo "📍 Path: $repo_path"
  echo ""
  
  if [[ -d "$repo_path/.git" ]]; then
    echo "🔧 Git Repository"
    echo ""
    if command -v git >/dev/null; then
      cd "$repo_path" 2>/dev/null && {
        echo "📊 Latest commits:"
        git log --oneline --color=always -8 2>/dev/null || echo "  No commit history"
        echo ""
        echo "🌿 Branches:"
        git branch -a --color=always 2>/dev/null | head -8 || echo "  No branches"
        echo ""
        echo "📈 Repository status:"
        git status --porcelain 2>/dev/null | head -5 | sed 's/^/  /' || echo "  Clean working directory"
      }
    fi
  else
    echo "📄 Directory contents:"
    ls -la "$repo_path" 2>/dev/null | head -15 || echo "  Cannot list directory"
  fi
}

_fzf_cd_ghq() {
  local root="$(ghq root)"
  local repo="$(ghq list | fzf --reverse --height=60% --preview="_ghq_preview $root/{}" --preview-window=right:50%)"
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
