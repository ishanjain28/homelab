{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.sonarr;
  environmentFile = "/run/container-secrets/sonarr.env";
in
{
  options.${namespace}.services.sonarr = mkServiceOptions {
    name = "sonarr";
    description = "Sonarr television collection manager";
    endpoints.web.port = 8989;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/sonarr/ping";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets.env = {
      file = "secrets/sonarr.env";
      format = "dotenv";
      mountPath = environmentFile;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };

    containerConfig = {
      services.sonarr = enabled // {
        openFirewall = false;
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
        environmentFiles = [ environmentFile ];
        settings.server = {
          bindaddress = "*";
          port = cfg.endpoints.web.port;
        };
      };

      systemd.services.sonarr.serviceConfig = {
        PrivateUsers = mkForce false;
        UMask = mkForce "0007";
      };
    };
  });
}
