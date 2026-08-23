{
  description = "Spenser's portable user environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      mkHome =
        {
          system,
          homeDirectory,
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
          ];
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
      };
    };
}
