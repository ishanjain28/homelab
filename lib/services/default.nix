{ lib, namespace, ... }:
with lib;
with lib.${namespace};
let
  containerUidOffset = 131072;
  containerProfiles = import ../containers/default.nix;
  inherit (containerProfiles)
    getNspawnHardeningProfile
    getNspawnIsolationProfile
    ;
  endpointType = types.submodule {
    options = {
      port = mkOption {
        type = types.port;
        description = "Port number.";
      };

      transport = mkOpt (types.enum [
        "tcp"
        "udp"
        "tcp-and-udp"
      ]) "tcp" "Transport protocol exposed through the container firewall.";

      expose = mkBoolOpt true "Whether to expose this endpoint through the container firewall.";
    };
  };

  portNumbersFor =
    protocol: endpoints:
    map (endpoint: endpoint.port) (
      filter (
        endpoint: endpoint.expose && (endpoint.transport == protocol || endpoint.transport == "tcp-and-udp")
      ) (attrValues endpoints)
    );

  mkContainerMacAddress =
    name:
    let
      hash = builtins.hashString "sha256" name;
      octet = offset: builtins.substring offset 2 hash;
    in
    "02:${octet 0}:${octet 2}:${octet 4}:${octet 6}:${octet 8}";

  # Container mechanics only: nspawn, bridge/VLAN, stable MAC, and host limits.
  genContainerBase =
    {
      name,
      vlans,
      config,
      isolationProfile ? "unprivileged",
      resources ? { },
    }:
    let
      isolationConfig = getNspawnIsolationProfile isolationProfile;
    in
    {
      # Generate the container entry
      containers.${name} = isolationConfig // {
        autoStart = true;
        privateNetwork = true;
        localMacAddress = mkContainerMacAddress name;
        # Plug into host bridge
        hostBridge = "br0";

        inherit config;
      };

      # Container Trunk Port (Host-side of the vbridge)
      systemd.network.networks."30-container-${name}" = {
        matchConfig.Name = "vb-${name}";
        networkConfig = {
          Bridge = "br0";
        };
        linkConfig.RequiredForOnline = "no";
        bridgeVLANs = [
          {
            VLAN = vlans;
          }
        ];
      };

      systemd.services."container@${name}".serviceConfig = {
        TimeoutStopSec = "25s";
      }
      // resources;
    };

  genContainerDefaults =
    {
      name,
      endpoints,
      vlans,
    }:
    let
      vlanInterface = vlan: "eth${toString vlan}";
      vlanNetdevs = listToAttrs (
        map (
          vlan:
          nameValuePair "20-${vlanInterface vlan}" {
            netdevConfig = {
              Name = vlanInterface vlan;
              Kind = "vlan";
            };
            vlanConfig.Id = vlan;
          }
        ) vlans
      );
      vlanNetworks = listToAttrs (
        imap0 (
          index: vlan:
          nameValuePair "40-${vlanInterface vlan}" {
            matchConfig.Name = vlanInterface vlan;
            networkConfig = {
              Description = "${name} service container VLAN ${toString vlan}";
              DHCP = "ipv4";
              LinkLocalAddressing = "ipv6";
              IPv6LinkLocalAddressGenerationMode = "eui64";
              IPv6PrivacyExtensions = "no";
              IPv6AcceptRA = "yes";
              LLDP = "no";
              EmitLLDP = "no";
              LLMNR = "no";
            };
            dhcpV4Config = {
              RouteMetric = 100 + index;
              UseDNS = index == 0;
              UseNTP = index == 0;
            };
            ipv6AcceptRAConfig = {
              DHCPv6Client = false;
              RouteMetric = 100 + index;
              Token = "eui64";
              UseDNS = index == 0;
            };
          }
        ) vlans
      );
    in
    {
      networking = {
        networkmanager = disabled;
        useHostResolvConf = false;
        firewall = enabled // {
          allowedTCPPorts = portNumbersFor "tcp" endpoints;
          allowedUDPPorts = portNumbersFor "udp" endpoints;
        };
      };

      # Fix for https://github.com/NixOS/nixpkgs/issues/493934
      security.pam.services.login.updateWtmp = mkForce false;

      documentation = disabled;
      environment.defaultPackages = mkForce [ ];
      environment.shellAliases = shellAliases;
      environment.systemPackages = mkForce [ ];
      nix = disabled;
      programs.command-not-found = disabled;
      services.logind = disabled;
      services.logrotate = disabled;
      services.nscd = disabled;
      services.getty = disabled;
      services.timesyncd = disabled;
      system.nssModules = mkForce [ ];
      systemd.oomd = enabled;
      systemd.services."console-getty" = disabled;
      systemd.services.systemd-networkd-persistent-storage = disabled;
      systemd.services.systemd-update-utmp = disabled;
      systemd.services.systemd-update-utmp-runlevel = disabled;
      systemd.services.systemd-user-sessions = disabled;
      services.journald.settings.Journal = {
        Storage = "persistent";
        SplitMode = "none";
        MaxRetentionSec = "1week";
        SystemMaxUse = "256M";
        RuntimeMaxUse = "64M";
      };

      systemd.network = enabled // {
        netdevs = vlanNetdevs;
        networks = vlanNetworks // {
          "30-eth0" = {
            matchConfig.Name = "eth0";
            linkConfig.RequiredForOnline = "carrier";
            networkConfig = {
              Description = "${name} service container VLAN trunk";
              DHCP = "no";
              LinkLocalAddressing = "no";
              IPv6AcceptRA = "no";
              LLDP = "no";
              EmitLLDP = "no";
              LLMNR = "no";
            };
            vlan = map vlanInterface vlans;
          };
        };
      };

      system.stateVersion = "26.05";
    };

  # Default homelab service container: minimal NixOS guest plus arbitrary inner config.
  genServiceContainer =
    {
      service,
      secrets ? { },
      containerConfig ? { },
      isolationProfile ? "unprivileged",
      resources ? { },
    }:
    let
      repoRoot = ../..;
      inherit (service)
        name
        runtimeId
        runtimeUser
        vlans
        ;
      mkSecretName = secretName: "${name}-${secretName}";
      mkHostUid = uid: containerUidOffset + uid;
      mkHostGid = gid: containerUidOffset + gid;
      mkSecretHostPath = secretName: "/run/homelab-container-secrets/${name}/${secretName}";
      secretHostUid = mkHostUid runtimeId;
      secretHostGid = mkHostGid runtimeId;
      mkSecretPrepareLine =
        secretName: _secret:
        let
          sopsName = mkSecretName secretName;
          hostPath = mkSecretHostPath secretName;
        in
        ''
          install -d -m 0700 -o root -g root ${escapeShellArg "/run/homelab-container-secrets/${name}"}
          install -m 0400 -o ${toString secretHostUid} -g ${toString secretHostGid} /run/secrets/${sopsName} ${escapeShellArg hostPath}
        '';
      secretConfig = mkMerge (
        mapAttrsToList (
          secretName: secret:
          let
            sopsName = mkSecretName secretName;
            inherit (secret) mountPath;
            hostPath = mkSecretHostPath secretName;
          in
          {
            sops.secrets.${sopsName} = {
              sopsFile = repoRoot + "/${secret.file}";
              inherit (secret) format;
              key = secret.key or "";
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = [ "container@${name}.service" ];
            };

            containers.${name}.bindMounts.${mountPath} = {
              inherit hostPath;
              isReadOnly = true;
            };
          }
        ) secrets
      );
    in
    mkMerge [
      secretConfig
      (mkIf (secrets != { }) {
        systemd.services."container@${name}".preStart = concatStringsSep "\n" (
          mapAttrsToList mkSecretPrepareLine secrets
        );
      })
      (genContainerBase {
        inherit
          name
          vlans
          isolationProfile
          resources
          ;
        config = mkMerge [
          (genContainerDefaults {
            inherit name vlans;
            inherit (service) endpoints;
          })
          {
            users.groups.${runtimeUser.group}.gid = mkForce runtimeId;
            users.users.${runtimeUser.name} = {
              isSystemUser = true;
              uid = mkForce runtimeId;
              group = mkForce runtimeUser.group;
            };
          }
          containerConfig
        ];
      })
    ];

  genServiceOptions =
    {
      name,
      description ? name,
      endpoints ? { },
      monitor ? disabled,
      logging ? enabled,
    }:
    let
      protocol = monitor.protocol or "tcp";
    in
    {
      enable = mkEnableOption name;

      name = mkOpt types.str name "Canonical service/container name.";

      description = mkOpt types.str description "Human-readable service description.";

      endpoints =
        mkOpt (types.attrsOf endpointType) endpoints
          "Named listener endpoints for this service.";

      vlans = mkOption {
        type = types.addCheck (types.nonEmptyListOf (types.ints.between 1 4094)) (
          vlans: length vlans == length (unique vlans)
        );
        description = "VLANs attached to this service container; the first is preferred for default routes and DNS.";
      };

      volumes = mkOpt (types.listOf types.str) [ ] "Volume IDs to attach to this service container.";

      shares =
        mkOpt (types.listOf types.str) [ ]
          "Shared host storage attached to this service container.";

      runtimeId =
        mkOpt (types.nullOr types.int) null
          "Stable numeric UID/GID for this service inside the container.";

      runtimeUser = {
        name = mkOpt types.str name "User that runs this service inside the container.";
        group = mkOpt types.str name "Group that runs this service inside the container.";
      };

      monitor = {
        enable = mkBoolOpt monitor.enable "Whether to generate a Gatus check for this service.";
        endpoint = mkOpt (types.nullOr types.str) (monitor.endpoint or null
        ) "Named endpoint checked by Gatus.";
        name = mkOpt types.str (monitor.name or name) "Gatus endpoint name.";
        group = mkOpt types.str (monitor.group or "services") "Gatus endpoint group.";
        protocol = mkOpt (types.enum [
          "http"
          "https"
          "tcp"
          "udp"
          "icmp"
          "icmpv6"
        ]) protocol "Gatus check protocol.";
        address = mkOpt types.str (monitor.address or "") "Gatus check address.";
        path = mkOpt types.str (monitor.path or "/") "Gatus HTTP path.";
        interval = mkOpt types.str (monitor.interval or "30s") "Gatus check interval.";
        conditions = mkOpt (types.listOf types.str) (monitor.conditions or (
          if protocol == "http" || protocol == "https" then
            [ "[STATUS] == 200" ]
          else
            [ "[CONNECTED] == true" ]
        )
        ) "Gatus check conditions.";
      };

      logging = {
        enable = mkBoolOpt logging.enable "Whether this service container should push journald logs to Loki.";
      };
    };

  # Convenience wrapper for the common one-container/one-systemd-service case.
  genSingleServiceContainer =
    {
      package ? null,
      command ? null,
      service,
      secrets ? { },
      exec ? "/bin/${service.name}",
      serviceName ? service.name,
      environment ? { },
      serviceConfig ? { },
      containerConfig ? { },
      isolationProfile ? "unprivileged",
      hardeningProfile ? "default",
      after ? [ ],
      wants ? [ ],
      resources ? { },
    }:
    let
      inherit (service) name;
      inherit (service) runtimeUser;
      hardeningConfig = getNspawnHardeningProfile hardeningProfile;
      execStart =
        if command != null then
          command
        else if package != null then
          "${package}${exec}"
        else
          throw "mkSingleServiceContainer '${name}' requires either 'command' or 'package'.";
    in
    genServiceContainer {
      inherit
        service
        isolationProfile
        resources
        secrets
        ;
      containerConfig = mkMerge [
        {
          systemd.services.${serviceName} = {
            inherit (service) description;
            inherit after wants;
            wantedBy = [ "multi-user.target" ];
            inherit environment;
            serviceConfig = {
              ExecStart = execStart;
              Restart = "always";
              TimeoutStopSec = "20s";
              DynamicUser = false;
              User = runtimeUser.name;
              Group = runtimeUser.group;
            }
            // hardeningConfig
            // optionalAttrs (service.shares != [ ]) {
              UMask = "0007";
            }
            // serviceConfig;
          };
        }
        containerConfig
      ];
    };
in
{
  inherit containerUidOffset;
  mkContainerBase = genContainerBase;
  mkServiceOptions = genServiceOptions;
  mkServiceContainer = genServiceContainer;
  mkSingleServiceContainer = genSingleServiceContainer;
}
