alias vi="nvim"
alias vim="nvim"

is_exist_command eza && {
  alias ls="eza"
  alias ll="eza -l"
  alias la="eza -la"
  alias lt="eza -T"
  alias l.="eza -d .*"
}

is_exist_command bat && {
  alias cat="bat -p"
}

is_exist_command fd && {
  alias find="fd"
}
