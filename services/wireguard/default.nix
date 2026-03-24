{
  lib,
  config,
  clanLib,
  ...
}: {
  _class = "clan.service";
  manifest.name = "wireguard-fullmesh";
  manifest.description = "WireGuard VPN in a full mesh topology";
  manifest.readme = "WireGuard mesh configuration. All peers connect to all other peers.";
  manifest.categories = ["Networking"];
  manifest.exports.out = [
    "networking"
    "peer"
  ];

  exports =
    lib.mapAttrs' (instanceName: _: {
      name = clanLib.buildScopeKey {
        inherit instanceName;
        serviceName = config.manifest.name;
      };
      value = {
        networking.priority = 1500;
      };
    })
    config.instances;

  # peer options and configuration
  roles.peer = {
    description = "Wireguard peer";
    interface = {
      options = {
        endpoint = lib.mkOption {
          type = lib.types.str;
          example = "node1.example.com";
          description = ''
            Endpoint where the peer can be reached
          '';
        };
        port = lib.mkOption {
          type = lib.types.int;
          default = 51820;
          description = ''
            Port where the peer can be reached
          '';
        };
        ipv4 = lib.mkOption {
          type = lib.types.str;
          example = "10.100.0.1";
          description = ''
            IPv4 address of the peer
          '';
        };
        ipv6 = lib.mkOption {
          type = lib.types.str;
          example = "fd00:1234:5678::1";
          description = ''
            IPv6 address of the peer
          '';
        };
      };
    };
    perInstance = {
      settings,
      instanceName,
      roles,
      ...
    }: {
      nixosModule = {config, ...}: let
        ipv4 = settings.ipv4;
        ipv6 = settings.ipv6;

        # extra hosts to add to /etc/hosts
        extraHostsIPv4 =
          lib.mapAttrsToList (
            name: _value: let
              ip = roles.peer.machines.${name}.settings.ipv4;
            in "${ip} ${name}.${instanceName}"
          )
          roles.peer.machines;
        extraHostsIPv6 =
          lib.mapAttrsToList (
            name: _value: let
              ip = roles.peer.machines.${name}.settings.ipv6;
            in "${ip} ${name}.${instanceName}"
          )
          roles.peer.machines;

        hostsContent = builtins.concatStringsSep "\n" (extraHostsIPv4 ++ extraHostsIPv6);
      in {
        # Enable ip forwarding, so wireguard peers can reach eachother
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        boot.kernel.sysctl."net.ipv6.ip_forward" = 1;

        networking = {
          extraHosts = hostsContent;
          firewall = {
            allowedUDPPorts = [settings.port];
            trustedInterfaces = [instanceName];
          };
        };

        networking.wireguard.interfaces."${instanceName}" = {
          ips = [
            "${ipv4}/24"
            "${ipv6}/64"
          ];
          listenPort = settings.port;

          peers = map (peer: {
            publicKey = (
              builtins.readFile (
                config.clan.core.settings.directory
                + "/vars/per-machine/${peer}/wireguard-${instanceName}/publickey/value"
              )
            );

            allowedIPs = [
              "${roles.peer.machines."${peer}".settings.ipv4}/32"
              "${roles.peer.machines."${peer}".settings.ipv6}/128"
            ];

            endpoint = "${roles.peer.machines."${peer}".settings.endpoint}:${
              builtins.toString roles.peer.machines."${peer}".settings.port
            }";

            persistentKeepalive = 15;
          }) (lib.attrNames roles.peer.machines);
        };
      };
    };
  };

  # Maps over all machines and produces one result per machine, regardless of role
  perMachine = {
    instances,
    machine,
    ...
  }: {
    nixosModule = {
      config,
      pkgs,
      ...
    }: {
      clan.core.vars.generators =
        lib.mapAttrs' (
          name: value:
          # Generate keys for each instance of the host
            lib.nameValuePair ("wireguard-" + name) {
              files.publickey.secret = false;
              files.privatekey = {};
              runtimeInputs = with pkgs; [wireguard-tools];
              script = ''
                wg genkey > $out/privatekey
                wg pubkey < $out/privatekey > $out/publickey
              '';
            }
        )
        instances;

      # Set the private key for each instance
      networking.wireguard.interfaces =
        builtins.mapAttrs (name: _: {
          privateKeyFile = "${config.clan.core.vars.generators."wireguard-${name}".files."privatekey".path}";
        })
        instances;
    };
  };
}
