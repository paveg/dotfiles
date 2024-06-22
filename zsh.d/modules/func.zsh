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

# This function is for 1password-cli
opr () {
    who=$(op whoami)
    if [[ $? != 0 ]]; then
        eval "$(op signin)"
    fi
    if [[ -f "$PWD/.env" ]]; then
        op run --env-file=$PWD/.env -- $@
    else
        op run --env-file=$HOME/.env.1password -- $@
    fi
}

function zprofiler() {
  ZSHRC_PROFILE=1 zsh -i -c zprof
}

function zshtime() {
  for i in $(seq 1 10); do time zsh -i -c exit >/dev/null; done
}
