# Profiling
if [ "$ZSHRC_PROFILE" != "" ]; then
	zmodload zsh/zprof && zprof >/dev/null
fi


source $ZMODPATH/core.zsh

: "Loading modules" && {
	declare -ax load_paths=(
		$ZMODPATH/util.zsh
		$ZMODPATH/plugin.zsh
		$ZMODPATH/local.zsh
		$ZMODPATH/alias.zsh
		$ZMODPATH/func.zsh
		$ZMODPATH/keybind.zsh
		$ZMODPATH/history.zsh
	)

	for load_path in ${load_paths[@]}; do
		load $load_path
		log_pass "Loading completed $(basename $load_path)"
	done
}

is_exist_command starship && eval "$(starship init zsh)" || echo "Not found starship: You can install it as curl -sS https://starship.rs/install.sh | sh"

typeset -U PATH fpath
