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
  cfg = srv.prowlarr;
  containerConfigPath = "/var/lib/prowlarr/config.xml";
in
{
  options.${namespace}.services.prowlarr = mkServiceOptions {
    name = "prowlarr";
    description = "Prowlarr indexer manager";
    endpoints.web.port = 9696;
    monitor = enabled // {
      endpoint = "web";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets.config = {
      file = "secrets/prowlarr.xml";
      format = "binary";
      mountPath = containerConfigPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };

    containerConfig = {
      services.prowlarr = enabled // {
        openFirewall = false;
        settings.server = {
          bindaddress = "*";
          port = cfg.endpoints.web.port;
        };
      };

      systemd.services.prowlarr.serviceConfig = {
        DynamicUser = mkForce false;
        User = cfg.runtimeUser.name;
        Group = cfg.runtimeUser.group;
        StateDirectoryMode = "0700";
        UMask = "0077";
      };
    };
  });
}
