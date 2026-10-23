{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.services.atuin;
  envPath = "/run/container-secrets/atuin.env";
in
{
  options.${namespace}.services.atuin = mkServiceOptions {
    name = "atuin";
    description = "Atuin shell history sync server";
    endpoints.web.port = 8888;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    serviceProfiles.atuin = "default";
    secrets.env = {
      file = "secrets/atuin.env";
      format = "dotenv";
      mountPath = envPath;
    };
    resources = {
      CPUQuota = "100%";
      MemoryMax = "256M";
      TasksMax = 256;
    };
    containerConfig = {
      services.atuin = enabled // {
        host = "::";
        port = cfg.endpoints.web.port;
        openRegistration = false;
        database.uri = null;
        environmentFile = envPath;
      };
    };
  });
}
