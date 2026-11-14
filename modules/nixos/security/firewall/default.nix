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

  callersOf =
    service: endpointName: endpoint:
    endpoint.from ++ optional (service.monitor.enable && service.monitor.endpoint == endpointName) "gatus";

  firewalledEndpoints =
    service: filterAttrs (_name: endpoint: endpoint.from != null && endpoint.expose) service.networking.endpoints;

  services = filterAttrs (
    _name: service: service.enable && service ? networking && firewalledEndpoints service != { }
  ) config.${namespace}.services;

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
        ++ [
          (
            if service.networking.firewall == "log" then
              ''ct state new ${match} log prefix "firewall ${service.name}/${endpointName}: " level info''
            else
              "${match} drop"
          )
        ]
      ) (firewalledEndpoints service)
    );

  callers = unique (
    concatLists (
      mapAttrsToList (_name: service: concatLists (mapAttrsToList (callersOf service) (firewalledEndpoints service))) services
    )
  );

  jumpToChain = concatLists (
    mapAttrsToList (
      name: service: map (vlan: ''"${mkContainerVethName name vlan}" : jump ${name}'') service.networking.vlans
    ) services
  );
in
{
  config = mkIf (services != { }) {
    networking.nftables.tables.homelab = {
      family = "bridge";
      content =
        concatMapStrings (caller: ''
          set ${caller} {
            type ipv6_addr
            elements = { ${concatStringsSep ", " (addressesOf caller)} }
          }
        '') callers
        + ''
          chain forward {
            type filter hook forward priority filter; policy accept;
            oifname vmap { ${concatStringsSep ", " jumpToChain} }
          }
        ''
        + concatStrings (
          mapAttrsToList (name: service: ''
            chain ${name} {
            ${concatMapStrings (rule: "  ${rule}\n") (rulesFor service)}}
          '') services
        );
    };
  };
}
