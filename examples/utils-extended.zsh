#!/usr/bin/env zsh
#
# 拡張版 utils.zsh
# 既存の機能に加えて、より詳細なOS/ディストリビューション検出機能を追加
#

# 既存の関数（変更なし）
is_osx() {
  [[ "$OSTYPE" == darwin* ]]
}

is_linux() {
  [[ "$OSTYPE" == linux* ]]
}

is_exist_command() {
  command -v "$1" &> /dev/null
}

# 新規: ディストリビューション検出
get_linux_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "$ID"
  elif [[ -f /etc/redhat-release ]]; then
    echo "rhel"
  elif [[ -f /etc/debian_version ]]; then
    echo "debian"
  else
    echo "unknown"
  fi
}

# 新規: ディストリビューションファミリー検出
get_linux_family() {
  local distro=$(get_linux_distro)
  case $distro in
    ubuntu|debian|mint|pop) echo "debian" ;;
    fedora|rhel|centos|rocky|almalinux) echo "redhat" ;;
    arch|manjaro|endeavouros) echo "arch" ;;
    opensuse*) echo "suse" ;;
    *) echo "unknown" ;;
  esac
}

# 新規: パッケージマネージャー検出
get_package_manager() {
  if is_osx; then
    echo "brew"
  elif is_linux; then
    local distro=$(get_linux_distro)
    case $distro in
      ubuntu|debian) echo "apt" ;;
      fedora) echo "dnf" ;;
      rhel|centos)
        # RHEL/CentOS 8以降はdnf、それ以前はyum
        if command -v dnf &> /dev/null; then
          echo "dnf"
        else
          echo "yum"
        fi
        ;;
      arch|manjaro) echo "pacman" ;;
      opensuse*) echo "zypper" ;;
      *) echo "unknown" ;;
    esac
  fi
}

# 新規: パッケージがインストールされているかチェック
is_package_installed() {
  local package=$1
  local pm=$(get_package_manager)
  
  case $pm in
    brew)
      brew list "$package" &> /dev/null
      ;;
    apt)
      dpkg -l "$package" 2> /dev/null | grep -q "^ii"
      ;;
    dnf|yum)
      rpm -q "$package" &> /dev/null
      ;;
    pacman)
      pacman -Q "$package" &> /dev/null
      ;;
    zypper)
      rpm -q "$package" &> /dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

# 新規: システムアーキテクチャ検出
get_arch() {
  local arch=$(uname -m)
  case $arch in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    i686) echo "386" ;;
    *) echo "$arch" ;;
  esac
}

# 新規: WSL検出
is_wsl() {
  [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ -n "$WSL_DISTRO_NAME" ]]
}

# 新規: Docker/コンテナ環境検出
is_container() {
  [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]]
}

# 改善: ロギング関数（カラー対応）
setup_colors() {
  if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
  else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    BOLD=''
    RESET=''
  fi
}

setup_colors

log_header() {
  echo -e "${BOLD}${PURPLE}==> $1${RESET}"
}

log_info() {
  echo -e "${BLUE}[INFO]${RESET} $1"
}

log_success() {
  echo -e "${GREEN}[OK]${RESET} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${RESET} $1" >&2
}

# 新規: 依存関係チェックヘルパー
require_command() {
  local cmd=$1
  local install_hint=$2
  
  if ! is_exist_command "$cmd"; then
    log_error "必要なコマンド '$cmd' が見つかりません"
    if [[ -n "$install_hint" ]]; then
      log_info "インストール方法: $install_hint"
    else
      local pm=$(get_package_manager)
      case $pm in
        brew) log_info "インストール方法: brew install $cmd" ;;
        apt) log_info "インストール方法: sudo apt install $cmd" ;;
        dnf) log_info "インストール方法: sudo dnf install $cmd" ;;
        pacman) log_info "インストール方法: sudo pacman -S $cmd" ;;
      esac
    fi
    return 1
  fi
  return 0
}

# 新規: バージョン比較
version_compare() {
  # Usage: version_compare current_version required_version
  # Returns: 0 if current >= required, 1 otherwise
  local current=$1
  local required=$2
  
  if [[ "$current" = "$required" ]]; then
    return 0
  fi
  
  local IFS=.
  local current_parts=($current)
  local required_parts=($required)
  
  for i in {0..2}; do
    local cur=${current_parts[i]:-0}
    local req=${required_parts[i]:-0}
    
    if (( cur > req )); then
      return 0
    elif (( cur < req )); then
      return 1
    fi
  done
  
  return 0
}

# 新規: 環境情報サマリー
print_environment_info() {
  log_header "環境情報"
  echo "OS: $(uname -s)"
  echo "Architecture: $(get_arch)"
  
  if is_osx; then
    echo "macOS Version: $(sw_vers -productVersion)"
  elif is_linux; then
    echo "Distribution: $(get_linux_distro)"
    echo "Distribution Family: $(get_linux_family)"
    if is_wsl; then
      echo "Environment: WSL"
    elif is_container; then
      echo "Environment: Container"
    fi
  fi
  
  echo "Package Manager: $(get_package_manager)"
  echo "Shell: $SHELL"
  echo "Zsh Version: $ZSH_VERSION"
}

# エクスポート
export -f is_osx
export -f is_linux
export -f is_exist_command
export -f get_linux_distro
export -f get_linux_family
export -f get_package_manager
export -f is_package_installed
export -f get_arch
export -f is_wsl
export -f is_container
export -f log_header
export -f log_info
export -f log_success
export -f log_warn
export -f log_error
export -f require_command
export -f version_compare
export -f print_environment_info