# ghtkn wiring (docs/design.md "GitHub authentication (ghtkn)"): the gh
# wrapper and the files it and ghtkn read from ~/.config/ghtkn, which come from
# the checkout on personal hosts and from the work profile on work-mac, where
# personal hosts render ghtkn.yaml themselves.
# linkHome links a path under home/ from the checkout (nix/home.nix).
{ config, lib, pkgs, host, linkHome, ... }:
let
  builds = import ./ghtkn.nix { inherit pkgs; };
  workProfile = name: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/dots-work/ghtkn/${name}";
  personal = host.profile == "personal";
  op = if pkgs.stdenv.hostPlatform.isDarwin then "op" else "op.exe";
in
{
  home.packages = [ builds.gh ];

  home.activation.ghtknConfig = lib.mkIf personal (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe builds.ghtkn-render} ${../home/.config/ghtkn/ghtkn.personal.yaml.tpl} ${lib.escapeShellArg "${config.xdg.configHome}/ghtkn/ghtkn.yaml"} ${op}
    ''
  );
  # home-manager starts its activation with an empty PATH, which would leave
  # the render step no op to find; it keeps the switch's PATH after its own.
  home.emptyActivationPath = lib.mkIf personal false;

  xdg.configFile =
    if host.profile == "work" then
      {
        "ghtkn/ghtkn.yaml".source = workProfile "ghtkn.yaml";
        "ghtkn/gh-app".source = workProfile "gh-app";
      }
    else
      { "ghtkn/gh-app".source = linkHome ".config/ghtkn/gh-app.personal"; };
}
