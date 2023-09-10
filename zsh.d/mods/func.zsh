function _fzf_cd_ghq() {
  local root="$(ghq root)"
  local repo="$(ghq list | fzf --preview="bat --color=always --style=header,grid --line-range :80 ${root}/{}/README.*")"
  local dir=$root/$repo
  if [[ -n $dir && $dir != $root/ ]]; then
    BUFFER="cd $dir"
    zle accept-line
  else
    zle reset-prompt
  fi
}

function zprofiler() {
  ZSHRC_PROFILE=1 zsh -i -c zprof
}

function zshtime() {
  for i in $(seq 1 10); do time zsh -i -c exit >/dev/null; done
}
