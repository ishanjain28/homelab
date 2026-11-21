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
    advertiseRoutes = mkOpt (listOf str) [ ] "Subnet routes to advertise through this node.";
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
      useRoutingFeatures = if cfg.advertiseRoutes == [ ] then "client" else "server";
      authKeyFile = config.sops.secrets.tailscale-auth-key.path;
      extraUpFlags = mkIf (cfg.advertiseRoutes != [ ]) [ "--advertise-routes=${concatStringsSep "," cfg.advertiseRoutes}" ];
      extraSetFlags = [ "--accept-dns=false" ];
    };

    boot.kernel.sysctl = mkIf (cfg.advertiseRoutes != [ ]) {
      "net.ipv4.ip_forward" = true;
      "net.ipv6.conf.all.forwarding" = true;
    };

    environment.systemPackages = [ cfg.package ];
  };
}
