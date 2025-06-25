# 機能担保チェックリスト

## ❌ テスト不足の重要機能

### 1. BUSINESS_USE環境変数の動作
- **状況**: 現在のCIでは`BUSINESS_USE=1`のテストなし  
- **影響**: work用Brewfileが正しく使われるかテストされていない
- **対応**: CI matrixにBUSINESS_USE=1の環境を追加必要

### 2. パフォーマンス最適化機能
- **mise lazy loading**: tmux/zellij環境での動作テストなし
- **atuin lazy loading**: 実際の履歴検索動作テストなし  
- **zsh startup time**: 実際の性能測定テストなし
- **zinit plugin loading**: plugin初期化の検証なし

### 3. 1Password統合
- **状況**: op plugin, ghコマンド統合のテストなし
- **影響**: 認証失敗時の動作が未検証
- **対応**: op pluginの条件付きロード動作テスト必要

### 4. ツール固有設定
- **Neovim**: AstroNvim設定の動作テストなし
- **Git**: freeeワーク設定、commit template動作テストなし
- **Starshipプロンプト**: 表示テストなし

### 5. XDG Base Directory準拠
- **状況**: ディレクトリ作成のみテスト済み
- **影響**: 各ツールが正しくXDGパスを使用するかテストなし

### 6. フォント管理
- **状況**: macOS/Linux でのフォントインストールテストなし
- **影響**: UDEVGothic フォントが正しく配置されるか未検証

### 7. エラーハンドリング
- **依存ツール不足**: mise, starship等の不足時の動作テストなし
- **権限エラー**: sudo権限なし環境でのテストなし
- **ネットワークエラー**: パッケージインストール失敗時のテストなし

## ✅ 十分テスト済みの機能

### 1. 基本ファイル配置
- ✅ .zshenv, .zshrc, .zprofile の作成・配置
- ✅ .config ディレクトリ構造の作成
- ✅ starship.toml の配置

### 2. OS固有動作
- ✅ macOS: Homebrew パス設定
- ✅ Linux: linuxbrew パス設定  
- ✅ 4つのOS環境での基本動作

### 3. Template描画
- ✅ chezmoi template の syntax check
- ✅ OS別変数の適用

### 4. CI環境での動作
- ✅ パッケージインストールのスキップ
- ✅ 権限が必要な操作のスキップ

## 🚨 追加すべきテスト

### Priority High
1. **BUSINESS_USE=1 環境のテスト**
2. **実際のzsh起動テスト** (syntax checkのみでは不十分)
3. **mise/atuin の lazy loading 動作テスト**

### Priority Medium  
4. **フォントインストールのテスト**
5. **1Password plugin のconditional loading テスト**
6. **エラー時のfallback動作テスト**

### Priority Low
7. **パフォーマンス測定の自動化**
8. **Neovim plugin 動作テスト**