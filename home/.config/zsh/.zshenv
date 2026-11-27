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
# process warn. Ask libc without starting a process, which every `zsh -c` would
# pay for: assigning LC_ALL makes zsh call setlocale, which keeps the locale it
# had when it cannot load the name, so the codeset after C then en_US.UTF-8
# says whether that loaded.
if zmodload zsh/langinfo 2>/dev/null &&
  () { local LC_ALL=C; LC_ALL=en_US.UTF-8; [[ $langinfo[CODESET] == UTF-8 ]] }; then
  export LANG=en_US.UTF-8
else
  export LANG=C.UTF-8
fi

export EDITOR=nvim
export VISUAL=nvim
export PAGER=less
export MANPAGER='less -R'

# kubectl reads only ~/.kube/config unless KUBECONFIG lists more files. A value
# the caller set is kept: every nested zsh runs this file.
if [[ -z ${KUBECONFIG-} ]]; then
  () {
    local kube_files=($HOME/.kube/config(N-.) $HOME/.kube/*.yaml(N-.))
    # A colon in a name would split it into two entries of the list.
    kube_files=(${kube_files:#*:*})
    if (( $#kube_files )); then
      export KUBECONFIG=${(j.:.)kube_files}
    fi
  }
fi

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
