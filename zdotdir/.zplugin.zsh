# https://github.com/zdharma-continuum/zinit
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[[ ! -d $ZINIT_HOME ]] && mkdir -p "$(dirname $ZINIT_HOME)"
[[ ! -d $ZINIT_HOME/.git ]] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# Plugin lists
## @see https://github.com/zdharma-continuum/zinit#turbo-and-lucid
zinit ice wait'0' depth"1" lucid blockf

# Highlighting syntax plugin
zinit light zdharma/fast-syntax-highlighting

# Command completion plugin
zinit light zsh-users/zsh-completions
autoload -Uz compinit && compinit
## Match both upper and lowercase
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
## Grouping each completion list
zstyle ':completion:*' format '%B%F{blue}%d%f%b'
zstyle ':completion:*' group-name ''
## If display completions menu, you can select completion by tab key or sth
zstyle ':completion:*:default' menu select=2
## Colorize completion candidates
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
## Keep prefix when completion
zstyle ':completion:*' keep-prefix
## Insert recent dirs when completion
zstyle ':completion:*' recent-dirs-insert both
## Completion candidate options
### _oldlist: Reuse the previous completion
### _complete: Complement command
### _match: Complement command from the list without opening globbing
### _history: History is included by completion candidates
### _ignored: Candidates for completion are also candidates for completion if you specify that they are not candidates for completion
### _approximate: Complete with similar completion candidates
### _prefix: Complete up to the cursor position, ignoring everything after the cursor
zstyle ':completion:*' completer _complete _ignored
## Cache completion candidates
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path ~/.zsh/cache
## Verbose for completion
zstyle ':completion:*' verbose yes
## If use sudo, search completion candidates
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin

# Command suggestion plugin
zinit light zsh-users/zsh-autosuggestions

# It’s a directory navigation tool
zinit light agkozak/zsh-z
