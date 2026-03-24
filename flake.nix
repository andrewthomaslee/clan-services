{
  description = "clan services";

  inputs = {
    clan-core.url = "github:clan-lol/clan-core";
    nixpkgs.follows = "clan-core/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    systems.url = "github:nix-systems/default";
  };

  outputs = inputs @ {
    flake-parts,
    systems,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import systems;

      imports = [
        inputs.clan-core.flakeModules.default
        ./services/flake-module.nix
      ];

      perSystem = {
        pkgs,
        system,
        ...
      }: {
        devShells.default = pkgs.mkShell {
          packages = [inputs.clan-core.packages.${system}.clan-cli];
        };
      };
    };
}
