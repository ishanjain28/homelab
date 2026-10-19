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
  cfg = srv.victorialogs;
in
{
  options.${namespace}.services.victorialogs = mkServiceOptions {
    name = "victorialogs";
    description = "VictoriaLogs log storage";
    endpoints.web.port = 9428;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/health";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    serviceProfiles.victorialogs = "default";
    resources = {
      CPUQuota = "400%";
      MemoryMax = "2G";
      TasksMax = 512;
    };
    containerConfig = {
      services.victorialogs = enabled // {
        listenAddress = ":${toString cfg.endpoints.web.port}";
        extraOptions = [
          "-enableTCP6"
          "-retentionPeriod=1y"
          "-retention.maxDiskSpaceUsageBytes=18GiB"
        ];
      };

      systemd.services.victorialogs.serviceConfig = {
        DynamicUser = mkForce false;
        User = cfg.runtimeUser.name;
        Group = cfg.runtimeUser.group;
      };
    };
  });
}
