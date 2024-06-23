# This is a profiling zshrc setting, set ZSHRC_PROFILE envvar to any value if you need.
if [ "$ZSHRC_PROFILE" != "" ]; then
	zmodload zsh/zprof && zprof >/dev/null
fi

eval "$(mise activate zsh --shims)"

source $ZMOD_PATH/core.zsh

: "Loading modules" && {
	declare -ax load_paths=(
        $ZMOD_PATH/utils.zsh # This must be load first after loading core.zsh
        $ZMOD_PATH/config.zsh
        $ZMOD_PATH/plugin.zsh
		$ZMOD_PATH/func.zsh
        $ZMOD_PATH/keybind.zsh
        $ZMOD_PATH/alias.zsh
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

eval "$(starship init zsh)"
source <(fzf --zsh)

typeset -U PATH fpath
