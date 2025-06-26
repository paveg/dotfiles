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
  # Validate required commands
  require_command ghq "ghq is required for repository navigation" || return $?
  require_command fzf "fzf is required for interactive selection" || return $?

  local root
  root="$(ghq root)" || {
    error "Failed to get ghq root directory"
    return 1
  }

  local repo="$(ghq list | fzf --reverse --height=60% \
    --preview="
      repo_path=$root/{}

      # Check for README files - if found, use bat directly
      if [[ -f \"\$repo_path/README.md\" ]]; then
        bat --color=always --style=header,grid --line-range :80 \"\$repo_path/README.md\"
      elif [[ -f \"\$repo_path/README.rst\" ]]; then
        bat --color=always --style=header,grid --line-range :80 \"\$repo_path/README.rst\"
      elif [[ -f \"\$repo_path/README.txt\" ]]; then
        bat --color=always --style=header,grid --line-range :80 \"\$repo_path/README.txt\"
      elif [[ -f \"\$repo_path/README\" ]]; then
        bat --color=always --style=header,grid --line-range :80 \"\$repo_path/README\"
      elif [[ -f \"\$repo_path/readme.md\" ]]; then
        bat --color=always --style=header,grid --line-range :80 \"\$repo_path/readme.md\"
      else
        echo \"\"
        echo \"📁 \$(basename \"\$repo_path\")\"
        echo \"📍 \$repo_path\"
        echo \"\"

        if [[ -d \"\$repo_path/.git\" ]]; then
          echo \"🔧 Git Repository\"
          cd \"\$repo_path\" 2>/dev/null && {
            echo \"\"
            echo \"📊 Recent commits:\"
            git log --oneline --color=always -8 2>/dev/null || echo \"  No commits\"
            echo \"\"
            echo \"🌿 Branches:\"
            git branch -a --color=always 2>/dev/null | head -8 || echo \"  No branches\"
          }
        else
          echo \"📄 Contents:\"
          ls -la \"\$repo_path\" 2>/dev/null | head -10 || echo \"  Cannot access\"
        fi
      fi
    " \
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
    # Validate 1Password CLI
    require_command op "1Password CLI (op) is required" || return $?

    # Check arguments
    [[ $# -eq 0 ]] && {
        error "Usage: opr <command>"
        return 1
    }

    # Check if signed in, sign in if needed
    local who
    who=$(op whoami 2>/dev/null)
    if [[ $? != 0 ]]; then
        debug "Signing into 1Password..."
        eval "$(op signin)" || {
            error "Failed to sign into 1Password"
            return 1
        }
    fi

    # Determine env file to use
    local env_file
    if [[ -f "$PWD/.env" ]]; then
        env_file="$PWD/.env"
        debug "Using local .env file: $PWD/.env"
    elif [[ -f "$HOME/.env.1password" ]]; then
        env_file="$HOME/.env.1password"
        debug "Using global .env file: $HOME/.env.1password"
    else
        error "No .env file found in current directory or ~/.env.1password"
        return 2
    fi

    # Execute command with env file
    op run --env-file="$env_file" -- "$@" || {
        error "Failed to execute command with 1Password"
        return 1
    }
}

zprofiler() {
  ZSHRC_PROFILE=1 zsh -i -c zprof
}

zshtime() {
  for i in $(seq 1 10); do time zsh -i -c exit >/dev/null; done
}

brewbundle() {
  local chezmoi_dir="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
  local brewfile

  # Select Brewfile based on BUSINESS_USE environment variable
  if [[ -n "$BUSINESS_USE" && "$BUSINESS_USE" != "0" ]]; then
    brewfile="$chezmoi_dir/homebrew/Brewfile.work"
    echo "Using business Brewfile (BUSINESS_USE=$BUSINESS_USE)"
  else
    brewfile="$chezmoi_dir/homebrew/Brewfile"
    echo "Using personal Brewfile"
  fi

  if [[ ! -f "$brewfile" ]]; then
    echo "Error: Brewfile not found at $brewfile" >&2
    echo "Available Brewfiles:"
    ls -la "$chezmoi_dir/homebrew/"Brewfile* 2>/dev/null || echo "  No Brewfiles found"
    return 1
  fi

  echo "Updating $brewfile with current packages..."
  brew bundle dump --verbose --force --cleanup --cask --formula --mas --tap --file="$brewfile"
  echo "✓ Updated: $brewfile"
}

# Brewfile management utilities
brewbundle_work() {
  BUSINESS_USE=1 brewbundle
}

brewbundle_personal() {
  unset BUSINESS_USE
  brewbundle
}

brewbundle_diff() {
  local chezmoi_dir="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
  local personal_brewfile="$chezmoi_dir/homebrew/Brewfile"
  local work_brewfile="$chezmoi_dir/homebrew/Brewfile.work"

  if [[ ! -f "$personal_brewfile" || ! -f "$work_brewfile" ]]; then
    echo "Error: Both Brewfiles must exist for comparison"
    return 1
  fi

  echo "=== Differences between personal and work Brewfiles ==="
  echo "Lines in work Brewfile but not in personal:"
  comm -13 <(sort "$personal_brewfile") <(sort "$work_brewfile") | grep -v '^#' | grep -v '^$'
  echo ""
  echo "Lines in personal Brewfile but not in work:"
  comm -23 <(sort "$personal_brewfile") <(sort "$work_brewfile") | grep -v '^#' | grep -v '^$'
}

PROTECTED_BRANCHES='main|master|develop|staging'
_remove_unnecessary_branches() {
  # Validate git command and repository
  require_command git "git is required for branch management" || return $?

  # Check if we're in a git repository
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    error "Not in a git repository"
    return 1
  fi

  # Check if there are any merged branches to delete
  local merged_branches
  merged_branches=$(git branch --merged | egrep -v "\*|${PROTECTED_BRANCHES}")

  if [[ -z "$merged_branches" ]]; then
    debug "No merged branches to delete"
    return 0
  fi

  debug "Removing merged branches (excluding: $PROTECTED_BRANCHES)"
  echo "$merged_branches" | xargs git branch -d || {
    error "Failed to delete some branches"
    return 1
  }
}

# Local configuration management functions
local_config_init() {
  local config_path="${ZDOTDIR:-$HOME/.config/zsh}/local.zsh"

  if [[ -f "$config_path" ]]; then
    echo "Local config already exists: $config_path"
    echo "Use 'local_config_edit' to modify it."
    return 1
  fi

  # Call the function from local.zsh module
  if (( $+functions[create_local_template] )); then
    create_local_template
  else
    echo "Error: local.zsh module not loaded" >&2
    return 1
  fi
}

local_config_edit() {
  local config_path="${ZDOTDIR:-$HOME/.config/zsh}/local.zsh"

  if [[ ! -f "$config_path" ]]; then
    echo "Local config doesn't exist. Creating template..."
    local_config_init || return 1
  fi

  "${EDITOR:-vim}" "$config_path"
}

local_config_show() {
  local config_path="${ZDOTDIR:-$HOME/.config/zsh}/local.zsh"

  if [[ -f "$config_path" ]]; then
    echo "=== Local Config: $config_path ==="
    cat "$config_path"
  else
    echo "No local config found. Use 'local_config_init' to create one."
  fi

  # Check other locations
  if [[ -f "$HOME/.zsh_local" ]]; then
    echo "=== Traditional Local Config: $HOME/.zsh_local ==="
    cat "$HOME/.zsh_local"
  fi

  if [[ -d "${ZDOTDIR:-$HOME/.config/zsh}/local" ]]; then
    echo "=== Local Config Directory: ${ZDOTDIR:-$HOME/.config/zsh}/local/ ==="
    ls -la "${ZDOTDIR:-$HOME/.config/zsh}/local/"
  fi
}
