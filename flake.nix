{
  description = "clan services";

  inputs = {
    # Clan.lol
    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
      inputs.flake-parts.follows = "flake-parts";
    };
    nixpkgs.follows = "clan-core/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    import-tree.url = "github:vic/import-tree";

    systems.url = "github:nix-systems/default";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;

      imports = [
        inputs.clan-core.flakeModules.default
        (inputs.import-tree ./modules)
      ];

      clan.modules = {
        cluster-mesh = ./services/cluster-mesh;
      };
    };
}
