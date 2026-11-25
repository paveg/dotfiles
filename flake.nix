{
  description = "Agent-first dotfiles for macOS and WSL2";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nix-darwin, home-manager, ... }:
    let
      # Unfree by name, never wholesale. It lives here rather than in
      # nix/packages.nix because the macOS modules bring unfree packages of
      # their own.
      nixpkgsConfig = {
        allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ];
      };
      darwinHost =
        name:
        let
          host = import ./hosts/${name}.nix;
        in
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit host; };
          modules = [
            { nixpkgs.config = nixpkgsConfig; }
            ./nix/darwin.nix
            home-manager.darwinModules.home-manager
          ];
        };
      wsl = import ./hosts/wsl.nix;
    in
    {
      # The agent hook builds, exposed so that CI can build and test them.
      packages = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (
        system: import ./nix/agents.nix { pkgs = nixpkgs.legacyPackages.${system}; }
      );

      darwinConfigurations = nixpkgs.lib.genAttrs [ "personal-mac" "work-mac" ] darwinHost;

      homeConfigurations."${wsl.user}@wsl" = home-manager.lib.homeManagerConfiguration {
        # Not legacyPackages: a standalone home-manager takes its nixpkgs
        # configuration from the pkgs it is handed.
        pkgs = import nixpkgs { system = wsl.system; config = nixpkgsConfig; };
        extraSpecialArgs = { host = wsl; };
        modules = [ ./nix/home.nix ];
      };
    };
}
