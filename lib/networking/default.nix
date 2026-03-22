# TODO: Maybe adapt this to work with systemd-networkd
# and NetworkManager if I ever decide to use both on
# different machines.
{ lib, ... }:
let
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

  # Shorthand for generating tagged vlan interfaces
  genBridgeIf = name: {
    netdevConfig = {
      Name = name;
      Kind = "bridge";
    };
    bridgeConfig = {
      VLANProtocol = "802.1q";
      VLANFiltering = "yes";
      DefaultPVID = "none";
      STP = "yes";
    };
  };

in
{
  mkIfLinks =
    data:
    builtins.listToAttrs (
      map (
        { name, macAddress }:
        let
          lowerAddress = lib.toLower macAddress;
          hash = builtins.hashString "sha256" lowerAddress;
        in
        {
          name = "10-${hash}";
          value = {
            matchConfig.PermanentMACAddress = lowerAddress;
            linkConfig.Name = name;
          };
        }
      ) data
    );

  mkBridgeIf = name: { "20-${name}" = genBridgeIf name; };
  mkBridgeIfList =
    params:
    builtins.listToAttrs (
      map (param: {
        name = "20-${param.name}";
        value = genBridgeIf param.name;
      }) params
    );

  mkTaggedVlanIf = id: { "20-vlan${toString id}" = genTaggedVlanIf id; };
  mkTaggedVlanIfList =
    ids:
    builtins.listToAttrs (
      map (id: {
        name = "20-vlan${toString id}";
        value = genTaggedVlanIf id;
      }) ids
    );

  mkNetworkIf =
    { name, config }:
    let
      hash = builtins.hashString "sha256" name;
    in
    {
      "40-${hash}" = {
        matchConfig.Name = name;
        networkConfig = config;
      };
    };

  mkNetworkIfList =
    data:
    builtins.listToAttrs (
      map (
        { name, config }:
        let
          hash = builtins.hashString "sha256" name;
        in
        {
          name = "40-${hash}";
          value = {
            matchConfig.Name = name;
            networkConfig = config;
          };
        }
      ) data
    );
}
