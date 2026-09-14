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
  cfg = srv.bazarr;
  secretPath = "/run/container-secrets/bazarr.yml";
  configPath = "/var/lib/bazarr/config/config.yaml";
in
{
  options.${namespace}.services.bazarr = mkServiceOptions {
    name = "bazarr";
    description = "Bazarr subtitle manager";
    endpoints.web.port = 6767;
    monitor = enabled // {
      endpoint = "web";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets.config = {
      file = "secrets/bazarr.yml";
      format = "yaml";
      mountPath = secretPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };

    containerConfig = {
      services.bazarr = enabled // {
        openFirewall = false;
        listenPort = cfg.endpoints.web.port;
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
      };

      systemd.tmpfiles.settings."20-bazarr-config" = {
        "/var/lib/bazarr/config".d = {
          user = cfg.runtimeUser.name;
          group = cfg.runtimeUser.group;
          mode = "0700";
        };
        ${configPath}."C+" = {
          user = cfg.runtimeUser.name;
          group = cfg.runtimeUser.group;
          mode = "0600";
          argument = secretPath;
        };
      };

      systemd.services.bazarr = {
        serviceConfig.UMask = "0007";
      };
    };
  });
}
