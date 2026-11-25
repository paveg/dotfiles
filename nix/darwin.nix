{ host, ... }:
{
  nixpkgs.hostPlatform = host.system;

  # Determinate Nix manages Nix itself; nix-darwin aborts activation otherwise.
  nix.enable = false;

  system.primaryUser = host.user;
  users.users.${host.user}.home = "/Users/${host.user}";
  system.stateVersion = 6;

  home-manager = {
    useGlobalPkgs = true;
    # Packages land in /etc/profiles/per-user/<user>/bin, which $ZDOTDIR/.zshenv
    # puts on PATH.
    useUserPackages = true;
    extraSpecialArgs = { inherit host; };
    users.${host.user} = ./home.nix;
  };
}
