#!/bin/bash -eu

export PLATFORM

trap catch ERR

function catch() {
  log_fail "Failed to installation."
}

# utility functions ------------------------------

copy_str() {
  if [[ $# -eq 0 ]]; then
    cat <&0
  elif [[ $# -eq 1 ]]; then
    if [[ -f "$1" ]] && [[ -r "$1" ]]; then
      cat "$1"
    else
      echo "$1"
    fi
  else
    return 1
  fi
}

# lower returns a copy of the string with all letters mapped to their lower case.
lower() { # shellcheck disable=SC2120
  copy_str | tr "[:upper:]" "[:lower:]"
}

# upper returns a copy of the string with all letters mapped to their upper case.
upper() { # shellcheck disable=SC2120
  copy_str | tr "[:lower:]" "[:upper:]"
}

# ostype returns the lowercase OS name
ostype() { # shellcheck disable=SC2119
  uname | lower
}

# os_detect export the PLATFORM variable as you see fit
os_detect() {
  export PLATFORM
  case "$(ostype)" in
  *'linux'*) PLATFORM='linux' ;;
  *'darwin'*) PLATFORM='osx' ;;
  *) PLATFORM='unknown' ;;
  esac
}

# is_osx returns true if running OS is Macintosh
is_osx() {
  os_detect
  if [[ "$PLATFORM" = "osx" ]]; then
    return 0
  else
    return 1
  fi
}

# is_linux returns true if running OS is GNU/Linux
is_linux() {
  os_detect
  if [[ "$PLATFORM" = "linux" ]]; then
    return 0
  else
    return 1
  fi
}

is_exists() {
  command -v "$1" >/dev/null 2>&1
  return $?
}

is_not_exists() {
  if is_exists "$1"; then
    return 1
  else
    return 0
  fi
}

ink() {
  if [[ "$#" -eq 0 ]] || [[ "$#" -gt 2 ]]; then
    echo "Usage: ink <color> <text>"
    echo "Colors:"
    echo "  black, white, red, green, yellow, blue, purple, cyan, gray"
    return 1
  fi

  local open="\033["
  local close="${open}0m"
  local black="0;30m"
  local red="1;31m"
  local green="1;32m"
  local yellow="1;33m"
  local blue="1;34m"
  local purple="1;35m"
  local cyan="1;36m"
  local gray="0;37m"
  local white="$close"

  local text="$1"
  local color="$close"

  if [[ "$#" -eq 2 ]]; then
    text="$2"
    case "$1" in (black | red | green | yellow | blue | purple | cyan | gray | white)
      eval color="\$$1"
      ;;
    esac
  fi

  printf "${open}${color}${text}${close}"
}

logging() {
  if [[ "$#" -eq 0 ]] || [[ "$#" -gt 2 ]]; then
    echo "Usage: ink <fmt> <msg>"
    echo "Formatting Options:"
    echo "  TITLE, ERROR, WARN, INFO, SUCCESS"
    return 1
  fi

  local color=
  local text="$2"

  case "$1" in
  TITLE)
    color=yellow
    ;;
  ERROR | WARN)
    color=red
    ;;
  INFO)
    color=blue
    ;;
  SUCCESS)
    color=green
    ;;
  *)
    text="$1"
    ;;
  esac

  timestamp() {
    ink gray "["
    ink purple "$(date +%H:%M:%S)"
    ink gray "] "
  }

  timestamp
  ink "$color" "$text"
  echo
}

log_pass() {
  logging SUCCESS "$1"
}

log_fail() {
  logging ERROR "$1" 1>&2
}

log_warn() {
  logging WARN "$1"
}

log_info() {
  logging INFO "$1"
}

log_echo() {
  logging TITLE "$1"
}

# install function ------------------------

prepare() {
  if is_not_exists brew; then
    if is_not_exists ruby; then
      log_fail "not found ruby..."
      exit 1
    fi
    ruby -e "$(curl -fsSL https://githubusercontent.com/Homebrew/install/master/install)"
    log_pass "Homebrew installation is completed."
  else
    log_warn "Homebrew is already installed."
  fi
  log_info "Prepare Homebrew..."
  brew cleanup
  brew update
  brew tap --repair
  if is_linux; then
    git -C "/home/linuxbrew/.linuxbrew/Homebrew/Library/Taps/homebrew/homebrew-core" remote set-url origin https://github.com/Homebrew/linuxbrew-core.git
  fi
  log_pass "All green!"
}

setup_packages() {
  log_info "Install Packages..."
  while read -r pkg; do
    if ! brew list | grep "$pkg" &>/dev/null; then
      is_linux && { [[ "$pkg" = "reattach-to-user-namespace" ]] || [[ "$pkg" = "llvm" ]]; } && continue
      log_info "Installing $pkg..."
      if [[ "$pkg" = "saml2aws" ]]; then
        brew tap versent/homebrew-taps
      fi
      brew install "$pkg"
    else
      log_warn "$pkg is already installed"
    fi
  done < "$dotpath/pkg/brew.txt"
  log_pass "Packages installation is completed."
}

setup_applications() {
  log_info "Install Applications..."
  while read -r pkg; do
    if ! brew cask list | grep "$pkg" &>/dev/null; then
      log_info "Installing $pkg..."
      brew cask install "$pkg"
    else
      log_warn "$pkg is already installed."
    fi
  done < "$dotpath/pkg/brew_cask.txt"
  log_pass "Applications installation is completed."
}

link_tools() {
  log_info "symbolic link: $dotpath/.zshenv to $HOME/.zshenv"
  ln -sf "$dotpath/.zshenv" "$HOME/.zshenv"

  if [[ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" ]]; then
    export XDG_CONFIG_HOME="$HOME/.config"
    if [[ ! -e "$XDG_CONFIG_HOME" ]]; then
      mkdir -p "$XDG_CONFIG_HOME"
    fi
    log_info "path $dotpath/nvim/ to $XDG_CONFIG_HOME/nvim ."
    ln -s "$dotpath/nvim/" "$XDG_CONFIG_HOME/nvim"
    log_pass "linked nvim config directory"
  else
    log_warn "already linked nvim config directory."
  fi

  if [[ ! -e "$HOME/.tmux.conf" ]]; then
    log_info "path $dotpath/.tmux.conf to $HOME/.tmux.conf ."
    ln -s "$dotpath/.tmux.conf" "$HOME/.tmux.conf"
    log_pass "linked tmux config directory"
  else
    log_warn "already linked tmux config directory."
  fi
}

deploy_binary() {
  local binary_name="$1"
  if [[ ! -e "$HOME/bin/$binary_name" ]]; then
    if [[ ! -e "$HOME/bin" ]]; then
      mkdir -p "$HOME/bin"
    fi
    log_info "Not linking $binary_name ."
    ln -s "$dotpath/bin/$binary_name" "$HOME/bin/$binary_name"
    log_pass "Deploy completed $binary_name symbolic link."
  else
    log_warn "Already deployed $binary_name..."
  fi
}

# -----------------------------------------

if is_not_exists git; then
  log_fail "not found git..."
  exit 1
fi

log_info "start installing..."

readonly githubUser="paveg"
readonly githubRepo="dotfiles"
readonly dotpath="$HOME/src/github.com/paveg/dotfiles"
readonly repoUrl="https://github.com/$githubUser/$githubRepo.git"

# configuration brew cask
if [[ -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
  export HOMEBREW_CASK_OPTS="--appdir=/Applications"
fi

if [[ ! -d $dotpath ]]; then
  git clone "$repoUrl" "$dotpath"
fi

prepare
if is_osx; then
  setup_applications
fi
setup_packages

if [[ -z "${ZPLUG_HOME:-}" ]]; then
  ZPLUG_HOME=$HOME/.zplug
  export ZPLUG_HOME
fi
git clone https://github.com/zplug/zplug "$ZPLUG_HOME"

link_tools
deploy_binary "gcp-context"
deploy_binary "kube-context"
deploy_binary "wifi-info"

log_pass "dotfiles OK."
