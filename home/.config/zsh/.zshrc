# A host reached over SSH may have no terminfo for the TERM it was handed:
# Ghostty's, or the one tmux sets inside a pane.
if [[ $TERM == xterm-ghostty ]] && ! infocmp xterm-ghostty &>/dev/null; then
  export TERM=xterm-256color
elif [[ -n ${TMUX-} ]] && ! infocmp $TERM &>/dev/null; then
  export TERM=screen-256color
fi

# History stays in memory so that atuin is the only history on disk.
SAVEHIST=0
HISTSIZE=100000
unset HISTFILE

setopt INTERACTIVE_COMMENTS AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS NO_BEEP HIST_IGNORE_DUPS

# Before any other binding: EDITOR=nvim makes zsh start in the vi keymap, and a
# key bound before this line would land there.
bindkey -e

mkdir -p $XDG_CACHE_HOME/zsh

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path $XDG_CACHE_HOME/zsh/zcompcache

# The prefix of each PATH entry .zshenv adds, which covers every Nix profile.
fpath=(${^_dots_path:h}/share/zsh/site-functions(N/) $fpath)

autoload -Uz compinit
# -i: never ask about insecure directories, which would read from stdin without a tty.
compinit -i -d $XDG_CACHE_HOME/zsh/zcompdump

PROMPT='%~ %# '

# A program that died with mouse reporting on leaves the terminal printing
# escape sequences on scroll; turn it off once, at the first prompt.
autoload -Uz add-zsh-hook
dots-mouse-reporting-off() {
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l'
  add-zsh-hook -d precmd dots-mouse-reporting-off
}
add-zsh-hook precmd dots-mouse-reporting-off

if (( $+commands[ghq] && $+commands[fzf] )); then
  dots-ghq-cd() {
    local repo=$(ghq list --full-path | fzf)
    [[ -n $repo ]] || return
    BUFFER="cd ${(q)repo}"
    zle accept-line
  }
  zle -N dots-ghq-cd
  bindkey '^g' dots-ghq-cd
fi

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS="--height 60% --layout=reverse --border=rounded --margin=1 --padding=1
    --color=bg+:#292e42,bg:#1a1b26,spinner:#9ece6a,hl:#7aa2f7
    --color=fg:#c0caf5,header:#7aa2f7,info:#7dcfff,pointer:#f7768e
    --color=marker:#9ece6a,fg+:#c0caf5,prompt:#7dcfff,hl+:#7aa2f7
    --color=selected-bg:#33467c
    --preview-window=right:50%:border-left
    --bind=ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down"
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
  FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range :300 {}'"
  FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  FZF_ALT_C_OPTS="--preview 'eza --tree --icons --level=2 --color=always {} | head -n 50'"
  # Its script restores every option on the way out, zle included, which a
  # shell without a terminal ($TTY empty) refuses with an error. The zle option
  # itself still reads on while startup files run.
  if [[ -n $TTY ]]; then
    eval "$(fzf --zsh)"
  fi
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# After fzf, whose init script binds Ctrl+r too.
if (( $+commands[atuin] )); then
  eval "$(atuin init zsh --disable-up-arrow)"
fi

# Abbreviations instead of aliases: Space or Enter expands one typed as the
# whole command line, at the primary prompt, so the full command is what runs
# and what atuin records. Only names that are not a command already.
typeset -A dots_abbreviations=(
  g git
  ga 'git add'
  gaa 'git add --all'
  gb 'git branch'
  gc 'git commit'
  gcm 'git commit -m'
  gco 'git checkout'
  gcb 'git checkout -b'
  gd 'git diff'
  gds 'git diff --staged'
  gf 'git fetch'
  gl 'git log --oneline -20'
  gp 'git push'
  gpl 'git pull'
  gst 'git status'
  gsw 'git switch'
  gswc 'git switch -c'
  k kubectl
  lg lazygit
  v nvim
)
dots-abbreviation-expand() {
  if [[ $CONTEXT == start && -z $PREBUFFER && -z $RBUFFER &&
    -n $LBUFFER && -n ${dots_abbreviations[$LBUFFER]-} ]]; then
    LBUFFER=${dots_abbreviations[$LBUFFER]}
  fi
}
dots-abbreviation-space() {
  dots-abbreviation-expand
  zle self-insert
}
dots-abbreviation-accept() {
  dots-abbreviation-expand
  zle accept-line
}
zle -N dots-abbreviation-space
zle -N dots-abbreviation-accept
bindkey ' ' dots-abbreviation-space
bindkey '^m' dots-abbreviation-accept

# The first profile on PATH that has each plugin. zsh-syntax-highlighting wraps
# the widgets that exist when it loads, so it comes after every other one.
for dots_plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  dots_plugin_files=(${^_dots_path:h}/share/$dots_plugin/$dots_plugin.zsh(N))
  if (( $#dots_plugin_files )); then
    source $dots_plugin_files[1]
  fi
done
unset dots_plugin dots_plugin_files
# zsh-autosuggestions would otherwise draw its suggestion again on the line the
# Enter widget has just accepted.
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(dots-abbreviation-accept)

if [[ -r $ZDOTDIR/.zshrc.local ]]; then
  source $ZDOTDIR/.zshrc.local
fi
