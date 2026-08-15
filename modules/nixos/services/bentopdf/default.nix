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
  srv = config.${namespace}.services;
  cfg = srv.bentopdf;
in
{
  options.${namespace}.services.bentopdf =
    mkServiceOptions {
      name = "bentopdf";
      monitor = {
        inherit (cfg) port;
        protocol = "http";
      };
    }
    // (with types; {
      port = mkOpt port 8080 "Listener Port";
    });

  config = mkIf cfg.enable (mkNspawnService {
    name = "bentopdf";
    description = "Bentopdf";
    vlan = 50;
    port = [ cfg.port ];
    package = pkgs.caddy;

    isolationProfile = "unprivileged";
    hardeningProfile = "default";

    resources = {
      CPUQuota = "100%";
      MemoryMax = "128M";
      TasksMax = 256;
    };

    serviceConfig = {
      ExecStart = "${pkgs.caddy}/bin/caddy file-server --listen :${toString cfg.port} --root ${pkgs.bentopdf}";
    };
  });
}
