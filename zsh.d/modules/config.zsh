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

# Keep 10000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=10000
SAVEHIST=10000

setopt histignorealldups sharehistory
