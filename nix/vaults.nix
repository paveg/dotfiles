# ghtkn wiring (docs/design.md "GitHub authentication (ghtkn)"): the gh
# wrapper and the files it and ghtkn read from ~/.config/ghtkn, which come from
# the checkout on personal hosts and from the work profile on work-mac.
# linkHome links a path under home/ from the checkout (nix/home.nix).
{ config, lib, pkgs, host, linkHome, ... }:
let
  builds = import ./ghtkn.nix { inherit pkgs; };
  workProfile = name: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/dots-work/ghtkn/${name}";
in
{
  home.packages = [ builds.gh ];

  xdg.configFile =
    if host.profile == "work" then
      {
        "ghtkn/ghtkn.yaml".source = workProfile "ghtkn.yaml";
        "ghtkn/gh-app".source = workProfile "gh-app";
      }
    else
      { "ghtkn/gh-app".source = linkHome ".config/ghtkn/gh-app.personal"; };
}
