#!/usr/bin/env zsh
# ============================================================================
# Key Bindings Configuration
#
# This file configures custom key bindings for enhanced shell interaction.
#
# Bindings:
# - Emacs-style key bindings as base
# - Alt (ESC): Interactive repository navigation via fzf
# - Ctrl+]: Interactive full-text search with ripgrep and fzf
# - Future: Additional custom bindings for productivity
# ============================================================================

# Module metadata declaration
declare_module "keybind" \
    "depends:platform,func" \
    "category:ui" \
    "description:Key bindings for enhanced shell interaction" \
    "provides:" \
    "external:" \
    "optional:"

bindkey -e

# _fzf_cd_ghq / Alt (ESC)
zle -N _fzf_cd_ghq
bindkey "^[" _fzf_cd_ghq

# _fzf_rg_search / Ctrl+]
zle -N _fzf_rg_search
bindkey "^]" _fzf_rg_search
