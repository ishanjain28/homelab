# TODO: Maybe adapt this to work with systemd-networkd
# and NetworkManager if I ever decide to use both on
# different machines.
{ lib, ... }:
let
  # Shorthand for generating interface link configuration
  genIfLink = { name, macAddress }: {
    matchConfig.PermanentMACAddress = macAddress;
    linkConfig.Name = name;
  };

  # Shorthand for generating tagged vlan interfaces
  genTaggedVlanIf = id: {
    netdevConfig = {
      Name = "vlan${toString id}";
      Kind = "vlan";
    };
    vlanConfig = {
      Id = id;
    };
  };

  # Shorthand for generating vlan aware bridge
  genBridgeIf = name: {
    netdevConfig = {
      Name = name;
      Kind = "bridge";
    };
    bridgeConfig = {
      VLANProtocol = "802.1q";
      VLANFiltering = "yes";
      DefaultPVID = "none";
      STP = "no";
    };
  };

  # Shorthand for generating network configuration
  genNetworkIf = { config, name }: config // { matchConfig.Name = name; };

  mkMacAddress =
    seed:
    let
      hash = builtins.hashString "sha256" seed;
      octet = offset: builtins.substring offset 2 hash;
    in
    "02:${octet 0}:${octet 2}:${octet 4}:${octet 6}:${octet 8}";

  ipv6Prefixes = {
    "10" = "2a0a:6040:4004:10";
    "20" = "2a0a:6040:4004:20";
    "30" = "2a0a:6040:4004:30";
    "40" = "2a0a:6040:4004:40";
    "50" = "2a0a:6040:4004:50";
    "99" = "2a0a:6040:4004:99";
  };

  mkIpv6Address =
    name: vlan:
    let
      hash = builtins.hashString "sha256" "${name}:${toString vlan}";
      octet = offset: builtins.substring offset 2 hash;
    in
    "${ipv6Prefixes.${toString vlan}}:${octet 0}:${octet 2}ff:fe${octet 4}:${octet 6}${octet 8}";

  ipv6Vlans = builtins.filter (vlan: ipv6Prefixes ? ${toString vlan});

  firewallGroups = {
    private = {
      ip = [
        "0.0.0.0/8"
        "10.0.0.0/8"
        "100.64.0.0/10"
        "127.0.0.0/8"
        "169.254.0.0/16"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "224.0.0.0/4"
        "240.0.0.0/4"
      ];
      ip6 = [ "2a0a:6040:4004::/48" ];
    };
    caddy = {
      ip = [ "10.0.50.3/32" ];
    };
    vlan140 = {
      ip = [ "10.0.140.0/24" ];
    };
    link-local = {
      ip = [ "169.254.0.0/16" ];
      ip6 = [ "fe80::/10" ];
    };
    all_lan = {
      ip = [ "10.0.0.0/16" ];
      ip6 = [ "2a0a:6040:4004::/48" ];
    };
    lan = {
      ip = [
        "10.0.10.0/24"
        "10.0.20.0/24"
        "10.0.30.0/24"
        "10.0.40.0/24"
      ];
      ip6 = [
        "2a0a:6040:4004:10::/64"
        "2a0a:6040:4004:20::/64"
        "2a0a:6040:4004:30::/64"
        "2a0a:6040:4004:40::/64"
      ];
    };
    trusted = {
      ip = [ "10.0.10.0/24" ];
      ip6 = [ "2a0a:6040:4004:10::/64" ];
    };
    mgmt = {
      ip = [ "10.0.99.0/24" ];
      ip6 = [ "2a0a:6040:4004:99::/64" ];
    };
    manaslu = {
      ip = [ "10.1.1.3/32" ];
      ip6 = [
        "2401:c080:3400:2e43:5400:4ff:fe5a:5550/128"
        "2a0a:6040:4004::1/128"
      ];
    };
  };
in
{
  inherit
    firewallGroups
    ipv6Vlans
    mkIpv6Address
    mkMacAddress
    ;

  mkIfLink =
    { name, macAddress }:
    let
      lowerAddress = lib.toLower macAddress;
      hash = builtins.hashString "sha256" lowerAddress;
    in
    {
      "10-${hash}" = genIfLink { inherit name macAddress; };
    };
  mkBridgeIf = name: { "20-${name}" = genBridgeIf name; };

  mkTaggedVlanIf = id: { "20-vlan${toString id}" = genTaggedVlanIf id; };

  mkNetworkIf =
    { config, name }:
    let
      hash = builtins.hashString "sha256" name;
    in
    {
      "40-${hash}" = genNetworkIf { inherit config name; };
    };
}
