function _fzf_cd_ghq() {
  local root="$(ghq root)"
  local repo="$(ghq list | fzf --preview="bat --color=always --style=header,grid --line-range :80 ${root}/{}/README.*")"
  local dir="${root}/${repo}"
  [[ -n "${dir}" ]] && cd "${dir}"
  zle accept-line
  zle reset-prompt
}
