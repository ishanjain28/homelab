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
  cfg = srv.lidarr;
  environmentFile = "/run/container-secrets/lidarr.env";
in
{
  options.${namespace}.services.lidarr = mkServiceOptions {
    name = "lidarr";
    description = "Lidarr music collection manager";
    endpoints.web.port = 8686;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/lidarr/ping";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    serviceProfiles.lidarr = [
      "jit"
      "procfs"
    ];
    secrets.env = {
      file = "secrets/lidarr.env";
      format = "dotenv";
      mountPath = environmentFile;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "512M";
      TasksMax = 512;
    };

    containerConfig = {
      services.lidarr = enabled // {
        openFirewall = false;
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
        environmentFiles = [ environmentFile ];
        settings.server = {
          bindaddress = "*";
          port = cfg.networking.endpoints.web.port;
        };
      };

      systemd.services.lidarr.serviceConfig = {
        UMask = mkForce "0007";
        Restart = mkForce "always";
      };
    };
  });
}
