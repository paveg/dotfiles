# Profiling
if [ "$ZSHRC_PROFILE" != "" ]; then
	zmodload zsh/zprof && zprof >/dev/null
fi

source $ZDOTDIR/.core.zsh
source $ZDOTDIR/.utils.sh

localconf=$HOME/.zshrc.local.zsh
if [[ -f $localconf ]]; then
	load $localconf
	log_info "Loaded local config from $localconf."
else
	log_info "Not found local configurations."
fi

# Load Plugins
load $ZDOTDIR/.zplugin.zsh
# Load aliases
load $ZDOTDIR/.zalias.zsh

setopt histignorealldups sharehistory

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e
# Use vim keybindings even if our EDITOR is set to vi
# bindkey -v

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history

[ -f "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh ] && load "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh

load $ZDOTDIR/.zfunc.zsh
load $ZDOTDIR/.zkeybindings.zsh
load $ZDOTDIR/.zfinalize.zsh
