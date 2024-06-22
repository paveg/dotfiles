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
