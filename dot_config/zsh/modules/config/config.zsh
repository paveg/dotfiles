#!/usr/bin/env zsh
# ============================================================================
# Zsh Basic Configuration
#
# This file contains basic Zsh settings and options.
# Currently focused on history management with plans for expansion.
#
# Features:
# - History configuration (size, deduplication, sharing)
# - Future: completion settings, key bindings, etc.
# ============================================================================

# Module metadata declaration
declare_module "config" \
  "depends:platform" \
  "category:config" \
  "description:Basic zsh configuration and options" \
  "provides:FZF_DEFAULT_OPTS" \
  "external:" \
  "optional:"

# History options (size is set in .zshenv)
setopt histignorealldups sharehistory

# fzf configuration
export FZF_DEFAULT_OPTS="--reverse --height=40% --border --margin=1 --padding=1"
