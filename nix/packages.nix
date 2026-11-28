{ pkgs, host, ... }:
{
  # The global CLI set and the zsh plugins, from docs/design.md "Packages",
  # then the host's own. `gh` is absent on purpose: nix/vaults.nix installs the
  # executable wrapper around ghtkn under that name.
  home.packages = with pkgs; [
    claude-code
    git
    ghq
    fzf
    ripgrep
    fd
    bat
    eza
    zoxide
    zsh-autosuggestions
    zsh-syntax-highlighting
    jq
    neovim
    just
    lazygit
    lefthook
    gitleaks
    kubectl
    kubernetes-helm
    k9s
    stern
    ghtkn
    mise
    uv
    rustup
    elan
    atuin
  ]
  ++ host.packages pkgs;
}
