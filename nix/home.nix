{ config, lib, pkgs, host, ... }:
let
  # Links point into the checkout, not the store, so edits apply without a switch.
  checkout = "${config.home.homeDirectory}/repos/github.com/paveg/dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${checkout}/home/${path}";
in
{
  imports = [ ./packages.nix ];

  home.username = host.user;
  home.homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/${host.user}" else "/home/${host.user}";
  home.stateVersion = "26.11";

  home.file.".zshenv".source = link ".zshenv";
  # One link per file, so ~/.config/zsh stays a real directory and .zshrc.local stays out of the checkout.
  xdg.configFile =
    lib.genAttrs [
      "zsh/.zshenv"
      "zsh/.zprofile"
      "zsh/.zshrc"
      "mise/config.toml"
      "git/config"
      "git/ignore"
      "git/personal.gitconfig"
    ] (path: {
      source = link ".config/${path}";
    });
}
