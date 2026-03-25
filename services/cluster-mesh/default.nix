{
  lib,
  config,
  clanLib,
  directory,
  ...
}: {
  _class = "clan.service";
  manifest.name = "cluster-mesh";
  manifest.description = "WireGuard VPN in a full mesh topology";
  manifest.readme = "WireGuard mesh configuration. All peers connect to all other peers.";
  manifest.categories = ["Networking"];

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
      nixosModule = {
        config,
        pkgs,
        ...
      }: let
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
        options.cluster-mesh.settings = {
          endpoint = lib.mkOption {
            type = lib.types.str;
            default = settings.endpoint;
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = settings.port;
          };
          ipv4 = lib.mkOption {
            type = lib.types.str;
            default = settings.ipv4;
          };
          ipv6 = lib.mkOption {
            type = lib.types.str;
            default = settings.ipv6;
          };
        };

        config = {
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
              "${settings.ipv4}/24"
              "${settings.ipv6}/64"
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

          environment.systemPackages = with pkgs; let
            peers = ''$(grep -oP '\S+\.${instanceName}' /etc/hosts | sort -u)'';
            runtimeInputs = [
              mtr
              fping
              gping
              trippy
              gnugrep
              coreutils
            ];
          in
            [
              (writeShellApplication {
                name = "mtr-${instanceName}";
                inherit runtimeInputs;
                text = ''
                  mtr "$@" -br \ ${peers}
                '';
              })
              (writeShellApplication {
                name = "fping-${instanceName}";
                inherit runtimeInputs;
                text = ''
                  fping "$@" -a -q -e -c 20 \ ${peers}
                '';
              })
              (writeShellApplication {
                name = "gping-${instanceName}";
                inherit runtimeInputs;
                text = ''
                  gping "$@" \ ${peers}
                '';
              })
              (writeShellApplication {
                name = "trippy-${instanceName}";
                inherit runtimeInputs;
                text = ''
                  trip "$@" \ ${peers}
                '';
              })
            ]
            ++ runtimeInputs;
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
              files.ipv4.secret = false;
              files.ipv6.secret = false;
              files.publickey.secret = false;
              files.privatekey = {};
              runtimeInputs = with pkgs; [wireguard-tools];
              script = ''
                wg genkey > $out/privatekey
                wg pubkey < $out/privatekey > $out/publickey

                printf "${config.cluster-mesh.settings.ipv4}" > $out/ipv4
                printf "${config.cluster-mesh.settings.ipv6}" > $out/ipv6
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

      boot.kernel.sysctl = {
        # Increase maximum socket buffer sizes to 32MB (for high BDP links)
        "net.core.rmem_max" = 33554432;
        "net.core.wmem_max" = 33554432;
        "net.core.rmem_default" = 1048576;
        "net.core.wmem_default" = 1048576;

        # Increase TCP buffer limits to 32MB as well
        "net.ipv4.tcp_rmem" = "4096 1048576 33554432";
        "net.ipv4.tcp_wmem" = "4096 65536 33554432";

        # Enable TCP BBR for much better high-latency throughput
        "net.core.default_qdisc" = "fq";
        "net.ipv4.tcp_congestion_control" = "bbr";

        # Optional: Increase network device backlog for high-speed local links
        "net.core.netdev_max_backlog" = 16384;
      };
    };
  };
}
