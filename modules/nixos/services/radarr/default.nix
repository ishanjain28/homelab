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
  cfg = srv.radarr;
  environmentFile = "/run/container-secrets/radarr.env";
in
{
  options.${namespace}.services.radarr = mkServiceOptions {
    name = "radarr";
    description = "Radarr movie collection manager";
    endpoints.web.port = 7878;
    monitor = enabled // {
      endpoint = "web";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets.env = {
      file = "secrets/radarr.env";
      format = "dotenv";
      mountPath = environmentFile;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };

    containerConfig = {
      services.radarr = enabled // {
        openFirewall = false;
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
        environmentFiles = [ environmentFile ];
        settings.server = {
          bindaddress = "*";
          port = cfg.endpoints.web.port;
        };
      };

      systemd.services.radarr.serviceConfig = {
        PrivateUsers = mkForce false;
        UMask = mkForce "0007";
      };
    };
  });
}
