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
  settingsPath = "/run/container-secrets/bazarr.yml";
in
{
  options.${namespace}.services.bazarr = mkServiceOptions {
    name = "bazarr";
    description = "Bazarr subtitle manager";
    endpoints.web.port = 6767;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/bazarr/ping";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    serviceProfiles.bazarr = "default";
    secrets.config = {
      file = "secrets/bazarr.yml";
      format = "yaml";
      mountPath = settingsPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "2G";
      TasksMax = 512;
    };

    containerConfig = {
      services.bazarr = enabled // {
        openFirewall = false;
        settings.general.port = cfg.endpoints.web.port;
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
      };

      systemd.services.bazarr = {
        preStart = "install -Dm600 ${settingsPath} /var/lib/bazarr/config/config.yaml";
        serviceConfig.UMask = "0007";
      };
    };
  });
}
