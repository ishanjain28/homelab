{
  config,
  inputs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  fleet = inputs.self.lib.homelabRegistry;
  site = config.${namespace}.hardware.networking.domain;
  siteServices = filter (service: fleet.hosts.${service.host}.domain == site) (attrValues fleet.services);

  addressesOf =
    ref:
    let
      matches = filter (service: service.name == ref) siteServices;
      vlans = ipv6Vlans (head matches).networking.vlans;
    in
    if matches == [ ] then
      throw "firewall: no service '${ref}' at ${site}"
    else if vlans == [ ] then
      throw "firewall: '${ref}' has no IPv6 address"
    else
      map (mkIpv6Address ref) vlans;

  isGroup = hasPrefix "@";

  groupRules =
    match: entry:
    let
      name = removePrefix "@" entry;
    in
    mapAttrsToList (family: cidrs: "${match} ${family} saddr { ${concatStringsSep ", " cidrs} } accept") (
      firewallGroups.${name} or (throw "firewall: unknown group '${name}'")
    );

  callersOf =
    service: endpointName: endpoint:
    filter (entry: !isGroup entry) endpoint.from
    ++ optional (service.monitor.enable && service.monitor.endpoint == endpointName) "gatus";

  firewalledEndpoints =
    service: filterAttrs (_name: endpoint: endpoint.from != null && endpoint.expose) service.networking.endpoints;

  enabledServices = filterAttrs (_name: service: service.enable && service ? networking) config.${namespace}.services;

  services = filterAttrs (
    _name: service: !service.networking.hostNetwork && firewalledEndpoints service != { }
  ) enabledServices;

  offline = filterAttrs (_name: service: !service.networking.internet) enabledServices;

  mkChain = name: rules: "chain ${name} {\n${concatMapStrings (rule: "  ${rule}\n") rules}}\n";

  verdict =
    service: label:
    let
      log = ''log prefix "firewall ${service.name}/${label}: " level info'';
    in
    if service.networking.firewall == "log" then log else "${log} drop";

  internetRules = service: [
    "ct state new ip daddr != { ${concatStringsSep ", " firewallGroups.private.ip} } ${verdict service "internet"}"
    "ct state new ip6 daddr 2000::/3 ip6 daddr != { ${concatStringsSep ", " firewallGroups.private.ip6} } ${verdict service "internet"}"
  ];

  rulesFor =
    service:
    concatLists (
      mapAttrsToList (
        endpointName: endpoint:
        let
          protocol = if endpoint.transport == "tcp-and-udp" then "{ tcp, udp }" else endpoint.transport;
          match = "meta l4proto ${protocol} th dport ${toString endpoint.port}";
        in
        map (caller: "${match} ip6 saddr @${caller} accept") (unique (callersOf service endpointName endpoint))
        ++ concatMap (groupRules match) (unique (filter isGroup endpoint.from))
        ++ [ "ct state new ${match} ${verdict service endpointName}" ]
      ) (firewalledEndpoints service)
    );

  callers = unique (
    concatLists (
      mapAttrsToList (_name: service: concatLists (mapAttrsToList (callersOf service) (firewalledEndpoints service))) services
    )
  );

  jumpToChain =
    suffix: selected:
    concatLists (
      mapAttrsToList (
        name: service: map (vlan: ''"${mkContainerVethName name vlan}" : jump ${name}${suffix}'') service.networking.vlans
      ) selected
    );

  forwardRules = [
    "type filter hook forward priority filter; policy accept;"
  ]
  ++ optional (services != { }) "oifname vmap { ${concatStringsSep ", " (jumpToChain "" services)} }"
  ++ optional (offline != { }) "iifname vmap { ${concatStringsSep ", " (jumpToChain "-internet" offline)} }";
in
{
  config = mkIf (services != { } || offline != { }) {
    networking.nftables.tables.homelab = {
      family = "bridge";
      content =
        concatMapStrings (caller: ''
          set ${caller} {
            type ipv6_addr
            elements = { ${concatStringsSep ", " (addressesOf caller)} }
          }
        '') callers
        + mkChain "forward" forwardRules
        + concatStrings (mapAttrsToList (name: service: mkChain name (rulesFor service)) services)
        + concatStrings (mapAttrsToList (name: service: mkChain "${name}-internet" (internetRules service)) offline);
    };
  };
}
