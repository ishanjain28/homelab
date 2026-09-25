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
  genNetworkIf = { config, name }: {
    matchConfig.Name = name;
    inherit (config) networkConfig ipv6AcceptRAConfig;
  };

in
{
  mkMacAddress =
    seed:
    let
      hash = builtins.hashString "sha256" seed;
      octet = offset: builtins.substring offset 2 hash;
    in
    "02:${octet 0}:${octet 2}:${octet 4}:${octet 6}:${octet 8}";

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
