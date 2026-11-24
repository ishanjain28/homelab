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
  cfg = srv.radarr-4k;
  environmentFile = "/run/container-secrets/radarr-4k.env";
in
{
  options.${namespace}.services.radarr-4k = mkServiceOptions {
    name = "radarr-4k";
    description = "Radarr 4K movie collection manager";
    endpoints.web.port = 7878;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/ping";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    databaseUnits = [ "radarr" ];
    serviceProfiles.radarr = [
      "jit"
      "procfs"
    ];
    secrets.env = {
      file = "secrets/radarr-4k.env";
      format = "dotenv";
      mountPath = environmentFile;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "768M";
      TasksMax = 512;
    };

    containerConfig = {
      services.radarr = enabled // {
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
        environmentFiles = [ environmentFile ];
        settings.server = {
          port = cfg.networking.endpoints.web.port;
        };
      };

      systemd.services.radarr.serviceConfig = {
        PrivateUsers = mkForce false;
        Restart = mkForce "always";
        UMask = mkForce "0007";
      };
    };
  });
}
