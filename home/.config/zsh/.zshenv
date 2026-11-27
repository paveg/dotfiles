typeset -U path PATH

_dots_path=(
  $HOME/.nix-profile/bin
  /etc/profiles/per-user/$USERNAME/bin
  /run/current-system/sw/bin
  /nix/var/nix/profiles/default/bin
  $HOME/.local/bin
  $XDG_DATA_HOME/mise/shims
  $XDG_DATA_HOME/aquaproj-aqua/bin
)
path=($_dots_path $path)

# A stock Ubuntu has only C.UTF-8, and a LANG it lacks makes every child
# process warn. glibc lists the locale as en_US.utf8, macOS as en_US.UTF-8.
if locale -a 2>/dev/null | grep -qiEx 'en_US\.utf-?8'; then
  export LANG=en_US.UTF-8
else
  export LANG=C.UTF-8
fi

export EDITOR=nvim
export VISUAL=nvim
export PAGER=less
export MANPAGER='less -R'

# Ubuntu's /etc/zsh/zshrc runs a compinit of its own, dumping into $ZDOTDIR,
# unless this is set; .zshrc runs the one compinit.
skip_global_compinit=1
export ATUIN_HOME=$XDG_DATA_HOME/atuin
# With ATUIN_HOME set, atuin reads and creates $ATUIN_HOME/config.toml unless
# this is set.
export ATUIN_CONFIG_DIR=$XDG_CONFIG_HOME/atuin

if [[ -r $HOME/.config/dots-work/env/static.env ]]; then
  source $HOME/.config/dots-work/env/static.env
fi
