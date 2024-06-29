bindkey -e

# _fzf_cd_ghq / ^g
zle -N _fzf_cd_ghq
bindkey "^[" _fzf_cd_ghq

if [[ -n $ZENO_LOADED ]]; then
  echo "zeno loaded"
  bindkey ' '  zeno-auto-snippet

  bindkey '^m' zeno-auto-snippet-and-accept-line
  bindkey '^i' zeno-completion
  bindkey '^x '  zeno-insert-space
  bindkey '^x^m' accept-line
  bindkey '^x^z' zeno-toggle-auto-snippet

  # bindkey '^r'   zeno-history-selection
  bindkey '^x^s' zeno-insert-snippet
  bindkey '^x^f' zeno-ghq-cd
fi

