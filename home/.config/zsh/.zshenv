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

export EDITOR=nvim

# Ubuntu's /etc/zsh/zshrc runs a compinit of its own, dumping into $ZDOTDIR,
# unless this is set; .zshrc runs the one compinit.
skip_global_compinit=1
export ATUIN_HOME=$XDG_DATA_HOME/atuin

if [[ -r $HOME/.config/dots-work/env/static.env ]]; then
  source $HOME/.config/dots-work/env/static.env
fi
