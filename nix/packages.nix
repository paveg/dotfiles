{ pkgs, host, ... }:
{
  # The global CLI set, from docs/design.md "Packages", then the host's own.
  # `gh` is absent on purpose: it becomes an executable wrapper around ghtkn,
  # not a package.
  home.packages = with pkgs; [
    claude-code
    git
    ghq
    fzf
    ripgrep
    fd
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
    atuin
  ]
  ++ host.packages pkgs;
}
