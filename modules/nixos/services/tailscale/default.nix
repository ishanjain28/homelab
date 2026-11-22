{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.services.tailscale;
in
{
  options.${namespace}.services.tailscale = with types; {
    enable = mkEnableOption "Tailscale";
    advertiseRoutes = mkOpt (listOf str) [
      "10.0.10.0/24"
      "10.0.20.0/24"
      "10.0.30.0/24"
      "10.0.40.0/24"
      "10.0.50.0/24"
      "10.0.60.0/24"
      "10.0.70.0/24"
      "10.0.99.0/24"
      "10.0.140.0/24"
      "10.0.150.0/24"
      "10.0.160.0/24"
    ] "Subnet routes to advertise through this node.";
    encryptState = mkBoolOpt true "Seal the node state with the TPM.";
    package = mkPackageOption pkgs "tailscale" { };
  };

  config = mkIf cfg.enable {
    sops.secrets.tailscale-auth-key = {
      sopsFile = repoFile "secrets/tailscale/auth-key";
      format = "binary";
    };

    services.tailscale = enabled // {
      inherit (cfg) package;
      openFirewall = true;
      useRoutingFeatures = "server";
      authKeyFile = config.sops.secrets.tailscale-auth-key.path;
      extraSetFlags = [
        "--accept-dns=false"
        "--advertise-exit-node"
        "--advertise-routes=${concatStringsSep "," cfg.advertiseRoutes}"
      ];
      extraDaemonFlags = mkIf cfg.encryptState [ "--encrypt-state" ];
    };

    environment.systemPackages = [ cfg.package ];
  };
}
