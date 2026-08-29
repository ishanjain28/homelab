{ lib, namespace, ... }:
with lib;
with lib.${namespace};
let
  inherit (lib)
    mkEnableOption
    mapAttrsToList
    mkMerge
    mkForce
    types
    ;
  containerUidOffset = 131072;
  containerProfiles = import ../containers/default.nix;
  inherit (containerProfiles)
    getNspawnHardeningProfile
    getNspawnIsolationProfile
    ;
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
      vlan,
      config,
      isolationProfile ? "unprivileged",
      macAddress ? mkContainerMacAddress name,
      resources ? { },
      specialArgs ? { },
    }:
    let
      isolationConfig = getNspawnIsolationProfile isolationProfile;
    in
    {
      # Generate the container entry
      containers.${name} = isolationConfig // {
        autoStart = true;
        privateNetwork = true;
        localMacAddress = macAddress;
        # Plug into host bridge
        hostBridge = "br0";

        inherit config;
        inherit specialArgs;
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
            VLAN = vlan;
            PVID = vlan;
            EgressUntagged = vlan;
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
      ports ? [ ],
    }:
    {
      networking = {
        networkmanager = disabled;
        useHostResolvConf = false;
        firewall = enabled // {
          allowedTCPPorts = ports;
        };
      };

      # Fix for https://github.com/NixOS/nixpkgs/issues/493934
      security.pam.services.login.updateWtmp = mkForce false;

      documentation = disabled;
      environment.defaultPackages = mkForce [ ];
      environment.systemPackages = mkForce [ ];
      nix = disabled;
      programs.command-not-found = disabled;
      services.logind = disabled;
      services.logrotate = disabled;
      services.nscd = disabled;
      services.getty = disabled;
      services.timesyncd = disabled;
      system.nssModules = mkForce [ ];
      systemd.oomd = disabled;
      systemd.services."console-getty" = disabled;
      systemd.services.systemd-networkd-persistent-storage = disabled;
      systemd.services.systemd-update-utmp = disabled;
      systemd.services.systemd-update-utmp-runlevel = disabled;
      systemd.services.systemd-user-sessions = disabled;
      services.journald = {
        storage = "persistent";
        extraConfig = ''
          SplitMode=none
          MaxRetentionSec=1week
          SystemMaxUse=256M
          RuntimeMaxUse=64M
        '';
      };

      systemd.network = enabled // {
        networks."30-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            Description = "${name} service container interface";
            DHCP = "ipv4";
            LinkLocalAddressing = "ipv6";
            IPv6LinkLocalAddressGenerationMode = "eui64";
            IPv6PrivacyExtensions = "no";
            IPv6AcceptRA = "yes";
            LLDP = "no";
            EmitLLDP = "no";
            LLMNR = "no";
          };
          ipv6AcceptRAConfig = {
            DHCPv6Client = false;
            Token = "eui64";
          };
        };
      };

      system.stateVersion = "26.05";
    };

  # Default homelab service container: minimal NixOS guest plus arbitrary inner config.
  genServiceContainer =
    {
      name,
      service,
      ports ? [ ],
      secrets ? { },
      containerConfig ? { },
      isolationProfile ? "unprivileged",
      macAddress ? mkContainerMacAddress name,
      resources ? { },
      specialArgs ? { },
    }:
    let
      repoRoot = ../..;
      inherit (service) runtimeId runtimeUser vlan;
      effectiveRuntimeUser = runtimeUser // {
        uid = if runtimeUser.uid != null then runtimeUser.uid else runtimeId;
        gid = if runtimeUser.gid != null then runtimeUser.gid else runtimeId;
      };
      mkSecretName = secretName: _secret: "${name}-${secretName}";
      mkContainerUid = secret: secret.uid or effectiveRuntimeUser.uid;
      mkContainerGid = secret: secret.gid or (mkContainerUid secret);
      mkHostUid = secret: containerUidOffset + mkContainerUid secret;
      mkHostGid = secret: containerUidOffset + mkContainerGid secret;
      mkSecretHostPath = secretName: "/run/homelab-container-secrets/${name}/${secretName}";
      mkSecretPrepareLine =
        secretName: secret:
        let
          sopsName = mkSecretName secretName secret;
          sourcePath = secret.path or "/run/secrets/${sopsName}";
          hostPath = mkSecretHostPath secretName;
        in
        ''
          install -d -m 0700 -o root -g root ${escapeShellArg "/run/homelab-container-secrets/${name}"}
          install -m ${secret.mode or "0400"} -o ${toString (mkHostUid secret)} -g ${toString (mkHostGid secret)} ${escapeShellArg sourcePath} ${escapeShellArg hostPath}
        '';
      secretConfig = mkMerge (
        mapAttrsToList (
          secretName: secret:
          let
            sopsName = mkSecretName secretName secret;
            inherit (secret) mountPath;
            hostPath = mkSecretHostPath secretName;
          in
          {
            sops.secrets.${sopsName} = {
              sopsFile = repoRoot + "/${secret.file}";
              format = secret.format or "binary";
              key = "";
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = secret.restartUnits or [ "container@${name}.service" ];
            }
            // optionalAttrs (secret ? path) { inherit (secret) path; };

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
      {
        systemd.services."container@${name}".preStart = concatStringsSep "\n" (
          mapAttrsToList mkSecretPrepareLine secrets
        );
      }
      (genContainerBase {
        inherit
          name
          vlan
          isolationProfile
          macAddress
          resources
          specialArgs
          ;
        config = mkMerge [
          (genContainerDefaults { inherit name ports; })
          {
            users.groups.${effectiveRuntimeUser.group}.gid = mkForce effectiveRuntimeUser.gid;
            users.users.${effectiveRuntimeUser.name} = {
              isSystemUser = true;
              uid = mkForce effectiveRuntimeUser.uid;
              group = mkForce effectiveRuntimeUser.group;
            };
          }
          containerConfig
        ];
      })
    ];

  genServiceOptions =
    {
      name,
      port ? null,
      monitor ? { },
    }:
    let
      protocol = monitor.protocol or "tcp";
    in
    {
      enable = mkEnableOption name;

      port = mkOpt (types.nullOr types.port) port "Primary listener port for this service container.";

      vlan = mkOption {
        type = types.port;
        description = "VLAN ID for this service container.";
      };

      volumes = mkOpt (types.listOf types.str) [ ] "Volume IDs to attach to this service container.";

      runtimeId =
        mkOpt (types.nullOr types.int) null
          "Stable numeric UID/GID for this service inside the container.";

      runtimeUser = {
        name = mkOpt types.str name "User that runs this service inside the container.";
        uid =
          mkOpt (types.nullOr types.int) null
            "Stable numeric UID for this service inside the container.";
        group = mkOpt types.str name "Group that runs this service inside the container.";
        gid =
          mkOpt (types.nullOr types.int) null
            "Stable numeric GID for this service inside the container.";
      };

      monitor = {
        enable = mkBoolOpt (monitor.enable or true) "Whether to generate a Gatus check for this service.";
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
        port = mkOpt (types.nullOr types.port) (monitor.port or null) "Gatus check port.";
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
        enable = mkBoolOpt true "Whether this service container should push journald logs to Loki.";
      };
    };

  # Convenience wrapper for the common one-container/one-systemd-service case.
  genSingleServiceContainer =
    {
      name,
      package ? null,
      command ? null,
      service,
      ports ? [ ],
      secrets ? { },
      description ? name,
      exec ? "/bin/${name}",
      serviceName ? name,
      environment ? { },
      serviceConfig ? { },
      containerConfig ? { },
      isolationProfile ? "unprivileged",
      hardeningProfile ? "default",
      macAddress ? mkContainerMacAddress name,
      after ? [ ],
      wants ? [ ],
      resources ? { },
      specialArgs ? { },
    }:
    let
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
        name
        service
        ports
        isolationProfile
        macAddress
        resources
        secrets
        ;
      specialArgs = specialArgs // {
        inherit package macAddress;
      };
      containerConfig = mkMerge [
        {
          systemd.services.${serviceName} = {
            inherit description;
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
