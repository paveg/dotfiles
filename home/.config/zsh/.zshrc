# History stays in memory so that atuin is the only history on disk.
SAVEHIST=0
HISTSIZE=100000
unset HISTFILE

setopt INTERACTIVE_COMMENTS AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS NO_BEEP HIST_IGNORE_DUPS

# Before any other binding: EDITOR=nvim makes zsh start in the vi keymap, and a
# key bound before this line would land there.
bindkey -e

mkdir -p $XDG_CACHE_HOME/zsh

autoload -Uz compinit
# -i: never ask about insecure directories, which would read from stdin without a tty.
compinit -i -d $XDG_CACHE_HOME/zsh/zcompdump

PROMPT='%~ %# '

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

if (( $+commands[atuin] )); then
  eval "$(atuin init zsh --disable-up-arrow)"
fi

if [[ -r $ZDOTDIR/.zshrc.local ]]; then
  source $ZDOTDIR/.zshrc.local
fi
