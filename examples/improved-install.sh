#!/usr/bin/env bash
#
# 改善されたインストールスクリプトの例
# クロスプラットフォーム対応と依存関係管理を強化
#

set -euo pipefail

# 既存のutils.zshから関数をロード
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../zsh.d/utils.zsh"

# 拡張: ディストリビューション検出
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

# 拡張: パッケージマネージャー検出
get_package_manager() {
  if is_osx; then
    echo "brew"
  elif is_linux; then
    local distro=$(get_linux_distro)
    case $distro in
      ubuntu|debian) echo "apt" ;;
      fedora|rhel|centos) echo "dnf" ;;
      arch|manjaro) echo "pacman" ;;
      opensuse*) echo "zypper" ;;
      *) echo "unknown" ;;
    esac
  fi
}

# 新規: 依存関係チェック関数
check_dependencies() {
  local deps=("eza" "bat" "fd" "rg" "fzf" "gh" "lazygit" "nvim" "mise" "delta" "starship")
  local missing=()
  
  log_info "依存関係をチェックしています..."
  
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      missing+=("$cmd")
    else
      log_success "$cmd: インストール済み"
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_warn "以下のコマンドが見つかりません: ${missing[*]}"
    return 1
  else
    log_success "全ての依存関係が満たされています"
    return 0
  fi
}

# 新規: パッケージ自動インストール
install_missing_packages() {
  local pm=$(get_package_manager)
  
  case $pm in
    brew)
      if [[ -f "${SCRIPT_DIR}/../homebrew/Brewfile" ]]; then
        log_info "Homebrewでパッケージをインストールします..."
        brew bundle --file="${SCRIPT_DIR}/../homebrew/Brewfile"
      fi
      ;;
    apt)
      if [[ -f "${SCRIPT_DIR}/../packages/apt.txt" ]]; then
        log_info "aptでパッケージをインストールします..."
        cat "${SCRIPT_DIR}/../packages/apt.txt" | xargs sudo apt-get install -y
      fi
      ;;
    dnf)
      if [[ -f "${SCRIPT_DIR}/../packages/dnf.txt" ]]; then
        log_info "dnfでパッケージをインストールします..."
        cat "${SCRIPT_DIR}/../packages/dnf.txt" | xargs sudo dnf install -y
      fi
      ;;
    pacman)
      if [[ -f "${SCRIPT_DIR}/../packages/pacman.txt" ]]; then
        log_info "pacmanでパッケージをインストールします..."
        cat "${SCRIPT_DIR}/../packages/pacman.txt" | xargs sudo pacman -S --noconfirm
      fi
      ;;
    *)
      log_warn "サポートされていないパッケージマネージャー: $pm"
      log_warn "手動でパッケージをインストールしてください"
      ;;
  esac
}

# 改善: フォントインストール（既存の機能を拡張）
install_fonts() {
  log_info "フォントをインストールしています..."
  
  if is_osx; then
    local font_dir="$HOME/Library/Fonts"
  elif is_linux; then
    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"
  else
    log_error "サポートされていないOS"
    return 1
  fi
  
  # フォントファイルをコピー
  find "${SCRIPT_DIR}/../fonts" -name "*.ttf" -o -name "*.otf" | while read -r font; do
    cp -f "$font" "$font_dir/"
    log_success "インストール: $(basename "$font")"
  done
  
  # Linuxの場合はフォントキャッシュを更新
  if is_linux && command -v fc-cache &> /dev/null; then
    log_info "フォントキャッシュを更新しています..."
    fc-cache -fv
  fi
}

# 新規: プラットフォーム別の設定
configure_platform_specific() {
  log_info "プラットフォーム固有の設定を適用しています..."
  
  if is_osx; then
    # macOS固有の設定
    if [[ -f "${SCRIPT_DIR}/../macos/defaults.sh" ]]; then
      log_info "macOSのデフォルト設定を適用..."
      bash "${SCRIPT_DIR}/../macos/defaults.sh"
    fi
  elif is_linux; then
    # Linux固有の設定
    local distro=$(get_linux_distro)
    if [[ -f "${SCRIPT_DIR}/../linux/${distro}.sh" ]]; then
      log_info "${distro}固有の設定を適用..."
      bash "${SCRIPT_DIR}/../linux/${distro}.sh"
    fi
  fi
}

# メイン処理
main() {
  log_header "改善されたdotfilesインストーラー"
  
  # OSとパッケージマネージャーの情報を表示
  log_info "OS: $(uname -s)"
  if is_linux; then
    log_info "Distribution: $(get_linux_distro)"
  fi
  log_info "Package Manager: $(get_package_manager)"
  
  # 依存関係のチェック
  if ! check_dependencies; then
    log_info "不足しているパッケージをインストールしますか？ [y/N]"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      install_missing_packages
      # 再度チェック
      check_dependencies
    fi
  fi
  
  # 既存のインストール処理を実行
  # （ここに元のinstall.shの処理を組み込む）
  
  # フォントのインストール
  install_fonts
  
  # プラットフォーム固有の設定
  configure_platform_specific
  
  log_success "インストールが完了しました！"
}

# エラーハンドリング
trap 'log_error "エラーが発生しました: line $LINENO"' ERR

# 実行
main "$@"