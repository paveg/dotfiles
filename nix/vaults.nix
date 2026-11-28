# ghtkn wiring (docs/design.md "GitHub authentication (ghtkn)"): the gh
# wrapper and the files it and ghtkn read from ~/.config/ghtkn, which come from
# the checkout on personal hosts and from the work profile on work-mac, where
# personal hosts render ghtkn.yaml themselves, and the ghtkn agent on wsl.
# linkHome links a path under home/ from the checkout (nix/home.nix).
{ config, lib, pkgs, host, linkHome, ... }:
let
  builds = import ./ghtkn.nix { inherit pkgs; };
  workProfile = name: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/dots-work/ghtkn/${name}";
  personal = host.profile == "personal";
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  # By path on macOS: nix-darwin activates under `env -i` with a PATH that
  # lacks /usr/local/bin, the one place the app integration accepts op.
  op = if isDarwin then "/usr/local/bin/op" else "op.exe";
in
{
  home.packages = [ builds.gh ];

  home.activation.ghtknConfig = lib.mkIf personal (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe builds.ghtkn-render} ${../home/.config/ghtkn/ghtkn.personal.yaml.tpl} ${lib.escapeShellArg "${config.xdg.configHome}/ghtkn/ghtkn.yaml"} ${op}
    ''
  );
  # On wsl op.exe is found on the Windows PATH of the shell that runs
  # `home-manager switch`, which home-manager drops from its activation unless
  # told to keep it.
  home.emptyActivationPath = lib.mkIf (personal && !isDarwin) false;

  # The agent on wsl, as nix/darwin.nix runs it on macOS.
  systemd.user.services.ghtkn-agent = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit.Description = "ghtkn agent";
    Service = {
      ExecStart = "${lib.getExe pkgs.ghtkn} agent start";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };

  xdg.configFile =
    if host.profile == "work" then
      {
        "ghtkn/ghtkn.yaml".source = workProfile "ghtkn.yaml";
        "ghtkn/gh-app".source = workProfile "gh-app";
      }
    else
      { "ghtkn/gh-app".source = linkHome ".config/ghtkn/gh-app.personal"; };
}
