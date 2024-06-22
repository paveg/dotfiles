source $ZMOD_PATH/core.zsh

: "Loading modules" && {
	declare -ax load_paths=(
        $ZMOD_PATH/utils.zsh # This must be load first after loading core.zsh
		$ZMOD_PATH/func.zsh
        $ZMOD_PATH/keybind.zsh
	)

	for load_path in ${load_paths[@]}; do
		load $load_path
		log_pass "Loading completed $(basename $load_path)"
	done
}

eval "$(starship init zsh)"
source <(fzf --zsh)

typeset -U PATH fpath
