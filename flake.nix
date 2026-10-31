{
  description = "Spenser's portable user environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    { nixpkgs, home-manager, plasma-manager, ... }:
    let
      mkHome =
        {
          system,
          homeDirectory,
          extraModules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home/common.nix
            {
              home = {
                username = "spenser";
                inherit homeDirectory;
              };
            }
          ] ++ extraModules;
        };
    in
    {
      homeConfigurations = {
        "spenser@macos" = mkHome {
          system = "aarch64-darwin";
          homeDirectory = "/Users/spenser";
        };

        "spenser@linux" = mkHome {
          system = "x86_64-linux";
          homeDirectory = "/home/spenser";
        };
        "spenser@linux-kde" = mkHome {
          system = "x86_64-linux";
          homeDirectory = "/home/spenser";
          extraModules = [
            plasma-manager.homeModules.plasma-manager
            ./home/kde.nix
          ];
        };
      };
    };
}
