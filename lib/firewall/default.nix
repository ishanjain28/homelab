{ lib, namespace, ... }: {
  firewallTypes = import ./types.nix { inherit lib; };
  firewallAddress = import ./address.nix { inherit lib; };
  compileFirewall = import ./compiler.nix {
    inherit lib;
    inherit (lib.${namespace}) mkMacAddress mkContainerVethName;
  };
}
