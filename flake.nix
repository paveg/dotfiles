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
      darwinHost =
        name:
        let
          host = import ./hosts/${name}.nix;
        in
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit host; };
          modules = [
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
        pkgs = nixpkgs.legacyPackages.${wsl.system};
        extraSpecialArgs = { host = wsl; };
        modules = [ ./nix/home.nix ];
      };
    };
}
