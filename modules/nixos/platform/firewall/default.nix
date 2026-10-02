{
  config,
  lib,
  namespace,
  inputs ? { },
  ...
}:
with lib;
let
  cfg = config.${namespace}.firewall;
  hostName = config.networking.hostName;
  types' = lib.${namespace}.firewallTypes;
  localServices = mapAttrs' (_: s: nameValuePair "${hostName}/${s.name}" (s // { host = hostName; })) (
    filterAttrs (_: s: s.enable) config.system.homelab.registry.services
  );
  extraServices = mapAttrs' (
    name: s:
    nameValuePair "${hostName}/${name}" (
      s
      // {
        inherit name;
        host = hostName;
      }
    )
  ) cfg.extraServices;
  services = cfg.peerServices // localServices // extraServices;
  active = filterAttrs (_: s: s.host == hostName && (s.networkPolicy.mode or "off") != "off") services;
  compiled = lib.${namespace}.compileFirewall {
    inherit hostName services;
    inherit (cfg) inventory;
    ipv4 = builtins.fromJSON (builtins.readFile cfg.ipv4File);
  };
  managed = attrValues active;
  containerSafe =
    s:
    let
      c = config.containers.${s.name} or null;
      explicit = s ? attachments;
    in
    c != null
    && c.privateNetwork
    && c.interfaces == [ ]
    && c.macvlans == [ ]
    && c.extraVeths == { }
    && c.networkNamespace == null
    && (
      if explicit then
        # Native untagged nspawn containers: only the standard bridge veth.
        c.hostBridge != null
        && c.extraFlags == [ ]
        && length (attrNames s.attachments) == 1
        && all (a: a.interface == "ve-${s.name}" && a.mac == c.localMacAddress) (attrValues s.attachments)
      else
        c.hostBridge == null
        && c.localAddress == null
        && c.hostAddress == null
        && c.localAddress6 == null
        && c.hostAddress6 == null
        && c.localMacAddress == null
        && all (
          flag:
          !(hasPrefix "--network" flag)
          || elem flag (map (v: "--network-veth-extra=${lib.${namespace}.mkContainerVethName s.name v}:eth${toString v}") s.vlans)
        ) c.extraFlags
    );
in
{
  options.${namespace}.firewall = {
    enable = mkEnableOption "host-owned service network policy";
    inventory = mkOption {
      type = types.attrs;
      default = import ../../../../network;
      description = "Network prefixes, router/DHCP identities, hosts, groups and infrastructure profiles.";
    };
    ipv4File = mkOption {
      type = types.path;
      default = ../../../../network/ipv4.json;
      description = "Unencrypted JSON: service name -> attachment -> expected IPv4 address.";
    };
    peerServices = mkOption {
      type = types.attrs;
      default = inputs.self.lib.homelabRegistry.services or { };
      description = "Fleet service metadata, used only to resolve explicit service references.";
    };
    extraServices = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            attachments = mkOption {
              type = types.attrs;
              description = "Explicit untagged host veth, MAC and network identities.";
            };
            endpoints = mkOption {
              type = types.attrs;
              default = { };
              description = "Named listening endpoints.";
            };
            networkPolicy = mkOption {
              type = types'.policy;
              default = { };
              description = "Native container policy.";
            };
          };
        }
      );
      default = { };
      description = "Policies for native nspawn containers outside the homelab service generator.";
    };
  };
  config = mkMerge [
    {
      assertions = [
        {
          assertion =
            cfg.enable || all (s: (s.networkPolicy.mode or "off") == "off") (attrValues (localServices // extraServices));
          message = "Service networkPolicy requires homelab.firewall.enable = true on this host.";
        }
      ];
    }
    (mkIf cfg.enable {
      assertions = [
        {
          assertion = !config.networking.nftables.flushRuleset;
          message = "Service policy requires atomic owned-table updates, not flushRuleset.";
        }
        {
          assertion = all containerSafe managed;
          message = "Managed service containers must have only their declared private bridge veth attachments.";
        }
      ];
      boot.kernelModules = [ "nf_conntrack_bridge" ];
      networking.nftables = {
        enable = true;
        tables.homelab_services = {
          family = "bridge";
          content = compiled.contents;
        };
      };
      # Retain rules on stop/restart, including failure paths. ExecStart/ExecReload
      # replace owned tables atomically using the upstream NixOS transaction.
      # BindsTo stops managed containers on firewall stop; After orders their stop
      # before nftables. Retention is an additional fail-closed boundary.
      systemd.services = {
        nftables.serviceConfig.ExecStop = mkForce [ ];
      }
      // listToAttrs (
        map (
          name:
          nameValuePair "container@${name}" {
            requires = [ "nftables.service" ];
            bindsTo = [ "nftables.service" ];
            after = [ "nftables.service" ];
          }
        ) compiled.containerNames
      );
      environment.etc."homelab/firewall.json".text = builtins.toJSON compiled.report;
      environment.etc."homelab/firewall.nft".text = "table bridge homelab_services {\n${compiled.contents}\n}\n";
    })
  ];
}
