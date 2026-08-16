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
  options.${namespace}.services.bentopdf = mkServiceOptions {
    name = "bentopdf";
    port = 8080;
    monitor = {
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    name = "bentopdf";
    description = "Bentopdf";
    inherit (cfg) vlan;
    ports = [ cfg.port ];

    resources = {
      CPUQuota = "100%";
      MemoryMax = "128M";
      TasksMax = 256;
    };

    command = "${pkgs.caddy}/bin/caddy file-server --listen :${toString cfg.port} --root ${pkgs.bentopdf}";
  });
}
