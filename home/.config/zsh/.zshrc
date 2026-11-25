# History stays in memory so that atuin is the only history on disk.
SAVEHIST=0
HISTSIZE=100000
unset HISTFILE

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
