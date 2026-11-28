{ config, lib, pkgs, host, ... }:
let
  # Links point into the checkout, not the store, so edits apply without a switch.
  checkout = "${config.home.homeDirectory}/repos/github.com/paveg/dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${checkout}/home/${path}";
  platform = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "wsl";
in
{
  imports = [
    ./packages.nix
    ./agents-home.nix
    ./vaults.nix
  ];

  _module.args.linkHome = link;

  home.username = host.user;
  home.homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/${host.user}" else "/home/${host.user}";
  home.stateVersion = "26.11";

  home.file.".zshenv".source = link ".zshenv";
  # A store copy, not a link into the checkout, so editing the repository never edits the live ~/.ssh/config.
  # On wsl, git hands ssh to Windows (wsl.gitconfig).
  home.file.".ssh/config" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin { source = ./ssh_config; };
  # One link per file, so ~/.config/zsh stays a real directory and .zshrc.local stays out of the checkout.
  xdg.configFile =
    lib.genAttrs [
      "zsh/.zshenv"
      "zsh/.zprofile"
      "zsh/.zshrc"
      "mise/config.toml"
      "atuin/config.toml"
      "git/config"
      "git/ignore"
      "git/personal.gitconfig"
    ] (path: {
      source = link ".config/${path}";
    })
    // {
      # The 1Password signer, and on wsl the ssh command, under the one name the git config includes.
      "git/platform.gitconfig".source = link ".config/git/${platform}.gitconfig";
    };
}
