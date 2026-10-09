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
    authKeyFile = mkOpt path "/run/secrets/tailscale-auth-key" "Path to a file containing a Tailscale auth key.";
    advertiseRoutes = mkOpt (listOf str) [ ] "Subnet routes to advertise through this node.";
    package = mkPackageOption pkgs "tailscale" { };
  };

  config = mkIf cfg.enable {
    services.tailscale = enabled // {
      inherit (cfg) package;
      openFirewall = true;
      useRoutingFeatures = if cfg.advertiseRoutes == [ ] then "client" else "server";
      inherit (cfg) authKeyFile;
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
