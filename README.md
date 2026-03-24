# clan-community

A community-maintained collection of [clan services](https://docs.clan.lol/25.11/services/definition/).
While [clan-core](https://git.clan.lol/clan/clan-core) ships a set of
officially supported services, this repository provides additional services
contributed and maintained by the community. Anyone is welcome to submit new
services or improve existing ones.

To learn how to create your own clan service, refer to the
[service definition guide](https://docs.clan.lol/25.11/services/definition/).

## Usage

Add `clan-community` as a flake input:

```nix
{
  inputs = {
    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
    clan-community.url = "https://git.clan.lol/clan/clan-community/archive/main.tar.gz";
    clan-community.inputs.clan-core.follows = "clan-core";
  };
}
```

Then use any service in your inventory:

```nix
clan.inventory.instances.<module-name> = {
  module.input = "clan-community";
  roles.<role>.machines = [ "my-machine" ];
};
```

For creating more instances of the same module:

```nix
clan.inventory.instances.<instance-2> = {
  module.name = "<module-name>";
  module.input = "clan-community";
  roles.<role>.machines = [ "my-machine" ];
};
```

## Services

- [wireguard](services/wireguard-star/README.md): WireGuard VPN Mesh

## Contributing

Each service lives in its own directory under `services/`:

```
services/<service-name>/
├── default.nix         # The clan service definition (_class = "clan.service")
├── flake-module.nix    # Registers the service via clan.modules.<name>
└── README.md           # Documentation
```

To add a new service:

1. Create a new directory under `services/`
2. Add a `default.nix` with your service definition
3. Add a `flake-module.nix` that registers it:
   ```nix
   { ... }:
   let
     module = ./default.nix;
   in
   {
     clan.modules.<service-name> = module;
   }
   ```
4. Add a `README.md` documenting the service, its roles, and usage

The service is auto-discovered — no central registration needed.
