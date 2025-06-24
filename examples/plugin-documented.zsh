#!/usr/bin/env zsh
# ============================================================================
# Zsh Plugin Management
# 
# このファイルはzinit（高速なZshプラグインマネージャー）を使用して
# 各種プラグインをロードします。
# 
# Zinitについて:
# - 並列ロード対応で高速
# - 遅延ロード機能
# - プラグインの更新管理
# - スニペット機能（OMZ/Preztoplugins対応）
#
# 使用方法:
# - `zinit update` : 全プラグインを更新
# - `zinit delete <plugin>` : プラグインを削除
# - `zinit times` : プラグインのロード時間を表示
# ============================================================================

# zinitのインストールチェックと自動インストール
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
  print -P "%F{33}▓▒░ %F{220}Installing %F{33}DHARMA%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
  command mkdir -p "$(dirname $ZINIT_HOME)"
  command git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" && \
    print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
    print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

source "${ZINIT_HOME}/zinit.zsh"

# ============================================================================
# プラグイン設定
# ============================================================================

# ----------------------------------------------------------------------------
# シンタックスハイライト
# コマンドラインの構文を色分けして表示
# 正しいコマンドは緑、エラーは赤で表示される
# ----------------------------------------------------------------------------
zinit wait lucid for \
  atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
    zdharma-continuum/fast-syntax-highlighting \
  blockf \
    zsh-users/zsh-completions \
  atload"!_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions

# ----------------------------------------------------------------------------
# 履歴検索の改善
# Ctrl+Rでインタラクティブな履歴検索
# fzfと連携して高速な検索を実現
# ----------------------------------------------------------------------------
zinit ice wait"0b" lucid atload'bindkey "^R" history-substring-search-up; bindkey "^S" history-substring-search-down'
zinit light zsh-users/zsh-history-substring-search

# ----------------------------------------------------------------------------
# ディレクトリ移動の改善
# zoxide: 頻繁に使用するディレクトリへの高速ジャンプ
# 使用例: z dotfiles → ~/repos/github.com/paveg/dotfiles へジャンプ
# ----------------------------------------------------------------------------
if command -v zoxide &> /dev/null; then
  zinit ice wait"0b" lucid
  zinit snippet https://github.com/ajeetdsouza/zoxide/blob/main/init.zsh
fi

# ----------------------------------------------------------------------------
# Git関連プラグイン
# ----------------------------------------------------------------------------

# git-open: GitリポジトリをブラウザーOPEN
# 使用例: git open → GitHubのリポジトリページを開く
zinit ice wait lucid
zinit light paulirish/git-open

# forgit: fzfを使用したインタラクティブなgitコマンド
# ga: インタラクティブ git add
# glo: インタラクティブ git log
# gd: インタラクティブ git diff
zinit ice wait lucid
zinit light 'wfxr/forgit'

# ----------------------------------------------------------------------------
# 補完機能の強化
# ----------------------------------------------------------------------------

# fzf-tab: タブ補完をfzfで置き換え
# 通常のタブ補完の代わりにfzfのインタラクティブな選択UIを提供
zinit ice wait"0b" lucid
zinit light Aloxaf/fzf-tab

# 補完スタイルの設定
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview 'less ${(Q)realpath}'
zstyle ':fzf-tab:*' switch-group ',' '.'

# ----------------------------------------------------------------------------
# プロンプトテーマ（Starshipを使用する場合はコメントアウト）
# ----------------------------------------------------------------------------
# zinit ice compile'(pure|async).zsh' pick'async.zsh' src'pure.zsh'
# zinit light sindresorhus/pure

# ----------------------------------------------------------------------------
# 便利なエイリアスとユーティリティ
# ----------------------------------------------------------------------------

# OMZ（Oh My Zsh）からの厳選されたプラグイン
zinit snippet OMZ::plugins/git/git.plugin.zsh
zinit snippet OMZ::plugins/colored-man-pages/colored-man-pages.plugin.zsh
zinit snippet OMZ::plugins/command-not-found/command-not-found.plugin.zsh

# ----------------------------------------------------------------------------
# パフォーマンス最適化
# ----------------------------------------------------------------------------

# コンパイル済みファイルの自動生成
zinit ice wait"0c" lucid atinit"zpcompinit; zpcdreplay"
zinit light zdharma-continuum/zinit-annex-bin-gem-node

# ----------------------------------------------------------------------------
# プラグインのロード完了後の処理
# ----------------------------------------------------------------------------

# 補完の初期化（高速化のため遅延実行）
autoload -Uz compinit
if [[ -n ${ZDOTDIR}/.zcompdump(#qNmh+24) ]]; then
  compinit
else
  compinit -C
fi

# zinit のコンパイル
zinit cdreplay -q

# ============================================================================
# プラグイン管理用エイリアス
# ============================================================================

alias zplug-update="zinit update --all"
alias zplug-clean="zinit delete --clean"
alias zplug-times="zinit times"
alias zplug-list="zinit list"

# ============================================================================
# トラブルシューティング
# 
# 問題: プラグインが正しくロードされない
# 解決: zinit delete <plugin> && zinit load <plugin>
# 
# 問題: 補完が効かない
# 解決: rm -f ~/.zcompdump && compinit
# 
# 問題: ロードが遅い
# 解決: zinit times でボトルネックを特定
# ============================================================================