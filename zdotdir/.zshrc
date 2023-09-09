source $ZDOTDIR/.utils.zsh

localconf=$HOME/.zshrc.local.zsh
if [[ -f $localconf ]]; then
	source $localconf
	log_info "Loaded local config from $localconf."
else
	log_info "Not found local configurations."
fi

# Load Plugins
source $ZDOTDIR/.zplugin.zsh
# Load aliases
source $ZDOTDIR/.zalias.zsh

setopt histignorealldups sharehistory

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e
# Use vim keybindings even if our EDITOR is set to vi
# bindkey -v

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history

[ -f "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh ] && source "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh

source $ZDOTDIR/.zfunc.zsh
source $ZDOTDIR/.zkeybindings.zsh
source $ZDOTDIR/.zfinalize.zsh
