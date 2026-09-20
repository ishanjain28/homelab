{ lib, namespace, ... }:
with lib;
with lib.${namespace};
let
  containerUidOffset = 131072;
  containerProfiles = import ../containers/default.nix;
  inherit (containerProfiles) getNspawnHardeningProfile getNspawnIsolationProfile;
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
      filter (endpoint: endpoint.expose && (endpoint.transport == protocol || endpoint.transport == "tcp-and-udp")) (
        attrValues endpoints
      )
    );

  mkContainerMacAddress =
    seed:
    let
      hash = builtins.hashString "sha256" seed;
      octet = offset: builtins.substring offset 2 hash;
    in
    "02:${octet 0}:${octet 2}:${octet 4}:${octet 6}:${octet 8}";

  mkContainerVethName =
    name: vlan:
    let
      hash = builtins.substring 0 9 (builtins.hashString "sha256" "${name}:${toString vlan}");
    in
    "v${hash}-${toString vlan}";

  # Container mechanics only: nspawn, bridge/VLAN, stable MAC, and host limits.
  genContainerBase =
    {
      name,
      vlans,
      config,
      isolationProfile ? "unprivileged",
      resources ? { },
      containerTimeout ? null,
    }:
    let
      isolationConfig = getNspawnIsolationProfile isolationProfile;
      containerVethFlags = map (vlan: "--network-veth-extra=${mkContainerVethName name vlan}:eth${toString vlan}") vlans;
      hostVethNetworks = listToAttrs (
        map (
          vlan:
          nameValuePair "30-container-${name}-${toString vlan}" {
            matchConfig.Name = mkContainerVethName name vlan;
            networkConfig.Bridge = "br0";
            linkConfig.RequiredForOnline = "no";
            bridgeVLANs = [
              {
                VLAN = vlan;
                PVID = vlan;
                EgressUntagged = vlan;
              }
            ];
          }
        ) vlans
      );
    in
    {
      # Generate the container entry
      containers.${name} = isolationConfig // {
        autoStart = true;
        privateNetwork = true;
        extraFlags = (isolationConfig.extraFlags or [ ]) ++ containerVethFlags;

        inherit config;
      };

      # Each host-side veth is an untagged access port for exactly one VLAN.
      systemd.network.networks = hostVethNetworks;

      systemd.services."container@${name}".serviceConfig = {
        TimeoutStartSec = mkForce (if containerTimeout == null then "1min" else containerTimeout);
        TimeoutStopSec = mkForce (if containerTimeout == null then "25s" else containerTimeout);
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
      vethLinks = listToAttrs (
        map (
          vlan:
          nameValuePair "20-${vlanInterface vlan}" {
            matchConfig.OriginalName = vlanInterface vlan;
            linkConfig.MACAddress = mkContainerMacAddress "${name}:${toString vlan}";
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
              ClientIdentifier = "mac";
              VendorClassIdentifier = "homelab-container/${name}";
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
    { config, ... }: {
      time.timeZone = timeZone;

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
      services.dbus.packages = [ config.systemd.package ];
      nix = disabled;
      programs.command-not-found = disabled;
      services.logind = disabled;
      services.logrotate = disabled;
      services.nscd = disabled;
      services.getty = disabled;
      services.timesyncd = disabled;
      system.nssModules = mkForce [ ];
      systemd.oomd = enabled;
      systemd.settings.Manager.ShowStatus = false;
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
        links = vethLinks;
        networks = vlanNetworks;
      };

      system.stateVersion = "26.05";
    };

  postgresqlSecretsFile = "secrets/postgresql.json";
  postgresqlInstances = builtins.fromJSON (builtins.readFile (../.. + "/${postgresqlSecretsFile}"));
  databaseReadyUnit = "database-ready.service";

  # Readiness gate and watchdog for a container that consumes a PostgreSQL database.
  genDatabaseClientConfig =
    service:
    { pkgs, ... }:
    let
      inherit (service) database;
      host = postgresqlInstances.${database.instance}.address;
      failureThreshold = 10;
      checkInterval = 30;
      check = "${pkgs.postgresql}/bin/pg_isready -q -h ${host} -p 5432 -d postgres -U ishan -t 5";
    in
    {
      systemd.services.database-ready = {
        description = "Wait for ${database.name} on ${database.instance}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "all";
          TimeoutStartSec = "infinity";
          Restart = "always";
          RestartSec = "5s";
        };
        script = ''
          until ${check}; do
            sleep 2
          done
          systemd-notify --ready

          failures=0
          while true; do
            sleep ${toString checkInterval}
            if ${check}; then
              if [ "$failures" -gt 0 ]; then
                echo "${database.instance} reachable again after $failures failed checks"
              fi
              failures=0
              continue
            fi
            failures=$(( failures + 1 ))
            if [ "$failures" -ge ${toString failureThreshold} ]; then
              echo "${database.instance} unreachable for $failures consecutive checks, restarting dependent units"
              systemctl --no-block restart ${databaseReadyUnit}
            fi
          done
        '';
      };
    };

  # Default homelab service container: minimal NixOS guest plus arbitrary inner config.
  genServiceContainer =
    {
      service,
      secrets ? { },
      containerConfig ? { },
      isolationProfile ? "unprivileged",
      resources ? { },
      containerTimeout ? null,
      databaseUnits ? [ service.name ],
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
      databaseEnabled = service.database != null;
      databaseUnitConfig = genAttrs databaseUnits (_unit: {
        after = [ databaseReadyUnit ];
        requires = [ databaseReadyUnit ];
      });
    in
    mkMerge [
      {
        sops.secrets = mapAttrs' (
          secretName: secret:
          nameValuePair (mkSecretName secretName) {
            sopsFile = repoRoot + "/${secret.file}";
            inherit (secret) format;
            key = secret.key or "";
            uid = containerUidOffset + runtimeId;
            gid = containerUidOffset + runtimeId;
            mode = "0400";
            restartUnits = [ "container@${name}.service" ];
          }
        ) secrets;

        containers.${name}.bindMounts = mapAttrs' (
          secretName: secret:
          nameValuePair secret.mountPath {
            hostPath = "/run/secrets/${mkSecretName secretName}";
            isReadOnly = true;
          }
        ) secrets;
      }
      (genContainerBase {
        inherit
          name
          vlans
          isolationProfile
          resources
          containerTimeout
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
          (mkIf databaseEnabled (mkMerge [
            (genDatabaseClientConfig service)
            { systemd.services = databaseUnitConfig; }
          ]))
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

      name = mkOpt types.nonEmptyStr name "Canonical service/container name.";

      description = mkOpt types.str description "Human-readable service description.";

      endpoints = mkOpt (types.attrsOf endpointType) endpoints "Named listener endpoints for this service.";

      vlans = mkOption {
        type = types.addCheck (types.nonEmptyListOf (types.ints.between 1 4094)) (vlans: length vlans == length (unique vlans));
        description = "VLANs attached to this service container; the first is preferred for default routes and DNS.";
      };

      volumes = mkOpt (types.listOf types.nonEmptyStr) [ ] "Volume IDs to attach to this service container.";

      shares = mkOpt (types.listOf types.nonEmptyStr) [ ] "Shared host storage attached to this service container.";

      devices = mkOpt (types.listOf types.nonEmptyStr) [ ] "Host devices attached to this service container.";

      runtimeId = mkOpt (types.nullOr types.int) null "Stable numeric UID/GID for this service inside the container.";

      runtimeUser = {
        name = mkOpt types.str name "User that runs this service inside the container.";
        group = mkOpt types.str name "Group that runs this service inside the container.";
      };

      monitor = {
        enable = mkBoolOpt monitor.enable "Whether to generate a Gatus check for this service.";
        endpoint = mkOpt (types.nullOr types.str) (monitor.endpoint or null) "Named endpoint checked by Gatus.";
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
        conditions = mkOpt (types.listOf types.str) (monitor.conditions
          or (if protocol == "http" || protocol == "https" then [ "[STATUS] == 200" ] else [ "[CONNECTED] == true" ])
        ) "Gatus check conditions.";
      };

      database = mkOpt (types.nullOr (
        types.submodule {
          options = {
            instance = mkOption {
              type = types.nonEmptyStr;
              description = "Name of the homelab PostgreSQL service that hosts the database.";
            };
            name = mkOpt types.nonEmptyStr name "Database name.";
          };
        }
      )) null "PostgreSQL database this service consumes.";

      logging = {
        enable = mkBoolOpt logging.enable "Whether this service container should push journald logs to Loki.";
        files = mkOpt (types.listOf types.str) [ ] "Log file paths or glob patterns that Alloy should also push to Loki.";
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
      containerTimeout ? null,
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
        containerTimeout
        secrets
        ;
      databaseUnits = [ serviceName ];
      containerConfig = mkMerge [
        {
          systemd.services.${serviceName} = {
            inherit (service) description;
            inherit after wants;
            wantedBy = [ "multi-user.target" ];
            inherit environment;
            unitConfig.StartLimitIntervalSec = 0;
            serviceConfig = {
              ExecStart = execStart;
              Restart = "always";
              RestartSec = "5s";
              TimeoutStopSec = "20s";
              DynamicUser = false;
              User = runtimeUser.name;
              Group = runtimeUser.group;
            }
            // hardeningConfig
            // optionalAttrs (service.shares != [ ]) { UMask = "0007"; }
            // serviceConfig;
          };
        }
        containerConfig
      ];
    };
in
{
  inherit
    containerUidOffset
    mkContainerVethName
    postgresqlInstances
    postgresqlSecretsFile
    ;
  mkServiceOptions = genServiceOptions;
  mkServiceContainer = genServiceContainer;
  mkSingleServiceContainer = genSingleServiceContainer;
}
