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
    description = "Bentopdf";
    endpoints.web.port = 8080;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;

    resources = {
      CPUQuota = "100%";
      MemoryMax = "128M";
      TasksMax = 256;
    };

    command = "${pkgs.caddy}/bin/caddy file-server --listen :${toString cfg.endpoints.web.port} --root ${pkgs.bentopdf}";
  });
}
