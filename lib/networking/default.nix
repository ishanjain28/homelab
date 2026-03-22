# TODO: Maybe adapt this to work with systemd-networkd
# and NetworkManager if I ever decide to use both on
# different machines.
{ lib, ... }:
let
  # Shorthand for generating tagged vlan interfaces
  genTaggedVlanIf =
    { id }:
    {
      netdevConfig = {
        Name = "vlan${toString id}";
        Kind = "vlan";
      };
      vlanConfig.Id = id;
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

  mkTaggedVlanIf = genTaggedVlanIf;

  mkTaggedVlanIfList =
    ids:
    builtins.listToAttrs (
      map (id: {
        name = "20-vlan${toString id}";
        value = genTaggedVlanIf { inherit id; };
      }) ids
    );

  mkNetworkIfList =
    data:
    builtins.listToAttrs (
      map (
        { name, config }:
        let
          hash = builtins.hashString "sha256" name;
        in
        {
          name = "30-${hash}";
          value = {
            matchConfig.Name = name;
            networkConfig = config;
          };
        }
      ) data
    );
}
