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
  cfg = srv.unpackerr;
  configPath = "/etc/unpackerr/unpackerr.conf";
in
{
  options.${namespace}.services.unpackerr = mkServiceOptions {
    name = "unpackerr";
    description = "Archive Unpackerr";
    monitor = disabled;
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets.config = {
      file = "secrets/unpackerr.conf";
      format = "binary";
      mountPath = configPath;
    };
    resources = {
      CPUQuota = "800%";
      MemoryMax = "4G";
      TasksMax = 512;
    };

    containerConfig = {
      services.unpackerr = enabled // {
        openFirewall = false;
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
      };

      systemd.services.unpackerr = {
        serviceConfig.UMask = "0007";
      };
    };
  });
}
