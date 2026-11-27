{ host, ... }:
{
  nixpkgs.hostPlatform = host.system;

  # Determinate Nix manages Nix itself; nix-darwin aborts activation otherwise.
  nix.enable = false;

  system.primaryUser = host.user;
  users.users.${host.user}.home = "/Users/${host.user}";
  system.stateVersion = 6;

  # $ZDOTDIR/.zshrc runs the one compinit, after it has put each profile's
  # completions on fpath, and sets its own prompt.
  programs.zsh = {
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
  };

  home-manager = {
    useGlobalPkgs = true;
    # Packages land in /etc/profiles/per-user/<user>/bin, which $ZDOTDIR/.zshenv
    # puts on PATH.
    useUserPackages = true;
    extraSpecialArgs = { inherit host; };
    users.${host.user} = ./home.nix;
  };
}
