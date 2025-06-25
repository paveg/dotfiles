#!/usr/bin/env zsh
# ============================================================================
# Zsh Plugin Management (Performance Optimized)
#
# This file manages Zsh plugins using zinit with aggressive performance tuning.
#
# Key optimizations:
# - Delayed loading with turbo mode for all plugins
# - Minimal completion system integration
# - Reduced plugin overhead
# - Async plugin loading where possible
#
# Commands:
# - `zinit update` : Update all plugins
# - `zinit delete <plugin>` : Remove a plugin
# - `zinit list` : List installed plugins
# ============================================================================

# Initialize zinit (optimized)
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Fast zinit installation check
if [[ ! -d $ZINIT_HOME/.git ]]; then
  [[ ! -d $ZINIT_HOME ]] && mkdir -p "$(dirname $ZINIT_HOME)"
  git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "${ZINIT_HOME}/zinit.zsh"

# Performance-optimized plugin loading with turbo mode
# All plugins delayed to avoid blocking shell startup

# Syntax highlighting (deferred)
zinit ice wait"0" lucid atinit"ZINIT[COMPINIT_OPTS]=-C; zpcompinit"
zinit light zdharma/fast-syntax-highlighting

# Completions (deferred, no compinit call - handled by init_completion)
zinit ice wait"0" lucid blockf
zinit light zsh-users/zsh-completions

# Completion styles (optimized set)
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' format '%B%F{blue}%d%f%b'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:default' menu select=2
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' completer _complete _ignored
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache"

# Essential plugins (deferred for performance)
zinit ice wait"1" lucid
zinit light zsh-users/zsh-autosuggestions

zinit ice wait"1" lucid
zinit light agkozak/zsh-z

zinit ice wait"1" lucid
zinit light zsh-users/zsh-history-substring-search

# atuin (handled by lazy loading in .zshrc, skip plugin installation)

# Completion plugins (deferred)
zinit ice wait"2" lucid as"completion"
zinit snippet https://github.com/docker/cli/blob/master/contrib/completion/zsh/_docker

zinit ice wait"2" lucid as"completion"
zinit snippet "https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/docker-compose/_docker-compose"

# Skip yarn completions (using PNPM only now)

zinit ice wait"2" lucid as"completion"
zinit snippet https://github.com/x-motemen/ghq/blob/master/misc/zsh/_ghq

zinit ice wait"2" lucid as"completion"
zinit snippet https://github.com/sharkdp/fd/blob/master/contrib/completion/_fd

# fzf integration (handled in .zshrc with conditional loading)
