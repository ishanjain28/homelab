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
  cfg = srv.victoriametrics;
in
{
  options.${namespace}.services.victoriametrics = mkServiceOptions {
    name = "victoriametrics";
    description = "VictoriaMetrics time series database";
    endpoints.web.port = 8428;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/health";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    serviceProfiles.victoriametrics = "default";
    resources = {
      CPUQuota = "400%";
      MemoryMax = "2G";
      TasksMax = 512;
    };
    containerConfig = {
      services.victoriametrics = enabled // {
        listenAddress = "0.0.0.0:${toString cfg.endpoints.web.port}";
        retentionPeriod = "1y";
        extraOptions = [ "-usePromCompatibleNaming" ];
      };

      systemd.services.victoriametrics.serviceConfig = {
        DynamicUser = mkForce false;
        User = cfg.runtimeUser.name;
        Group = cfg.runtimeUser.group;
      };
    };
  });
}
