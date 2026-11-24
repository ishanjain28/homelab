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
  cfg = srv.sonarr-4k;
  environmentFile = "/run/container-secrets/sonarr-4k.env";
in
{
  options.${namespace}.services.sonarr-4k = mkServiceOptions {
    name = "sonarr-4k";
    description = "Sonarr 4K television collection manager";
    endpoints.web.port = 8989;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/ping";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    databaseUnits = [ "sonarr" ];
    serviceProfiles.sonarr = [
      "jit"
      "procfs"
    ];
    secrets.env = {
      file = "secrets/sonarr-4k.env";
      format = "dotenv";
      mountPath = environmentFile;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "768M";
      TasksMax = 512;
    };

    containerConfig = {
      services.sonarr = enabled // {
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
        environmentFiles = [ environmentFile ];
        settings.server = {
          port = cfg.networking.endpoints.web.port;
        };
      };

      systemd.services.sonarr.serviceConfig = {
        PrivateUsers = mkForce false;
        Restart = mkForce "always";
        UMask = mkForce "0007";
      };
    };
  });
}
