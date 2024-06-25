# This is a profiling zshrc setting, set ZSHRC_PROFILE envvar to any value if you need.
if [ "$ZSHRC_PROFILE" != "" ]; then
  zmodload zsh/zprof && zprof >/dev/null
fi

source $ZMODDIR/core.zsh

: "Loading modules" && {
  declare -ax load_paths=(
    $ZMODDIR/utils.zsh # This must be load first after loading core.zsh
    $ZMODDIR/config.zsh
    $ZMODDIR/plugin.zsh
    $ZMODDIR/func.zsh
    $ZMODDIR/keybind.zsh
    $ZMODDIR/alias.zsh
  )

  for load_path in ${load_paths[@]}; do
    load $load_path
    log_pass "Loading completed $(basename $load_path)"
  done

  # TODO: Rename to localconf.zsh
  localconf=$HOME/.zshrc.local.zsh
  if [[ -f $localconf ]]; then
    log_info "Found local configuration file: $localconf"
    load $localconf
    log_pass "Loading completed $(basename $localconf)"
  fi
}

eval "$(atuin init zsh)"
eval "$(starship init zsh)"
source <(fzf --zsh)
eval "$(mise activate zsh)"

typeset -U PATH fpath
