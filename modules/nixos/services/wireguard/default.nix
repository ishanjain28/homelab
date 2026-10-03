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
  cfg = config.${namespace}.services.wireguard;
  interfaces = filterAttrs (_: interface: interface.enable) cfg.interfaces;
  secretName = name: "wireguard-${name}";
in
{
  options.${namespace}.services.wireguard = with types; {
    enable = mkBoolOpt false "Whether to enable WireGuard tunnels configured from SOPS secrets.";
    interfaces = mkOpt (attrsOf (submodule {
      options = {
        enable = mkBoolOpt true "Whether to enable this tunnel.";
        configFile = mkOpt str null "Repository-relative SOPS binary file with the complete wg-quick configuration.";
        listenPort = mkOpt (nullOr port) null "UDP port to open; must match ListenPort in the secret.";
      };
    })) { } "WireGuard interfaces by name.";
  };

  config = mkIf cfg.enable {
    sops.secrets = mapAttrs' (
      name: interface:
      nameValuePair (secretName name) {
        sopsFile = "${inputs.self}/${interface.configFile}";
        format = "binary";
        restartUnits = [ "wg-quick-${name}.service" ];
      }
    ) interfaces;

    networking.wg-quick.interfaces = mapAttrs (name: _: {
      type = "wireguard";
      configFile = config.sops.secrets.${secretName name}.path;
    }) interfaces;

    networking.firewall.allowedUDPPorts = filter (port: port != null) (
      mapAttrsToList (_: interface: interface.listenPort) interfaces
    );
  };
}
