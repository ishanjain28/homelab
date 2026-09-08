{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.multicaster;
  configDirectory = "/run/container-secrets";
  configPath = "${configDirectory}/config.toml";
in
{
  options.${namespace}.services.multicaster = mkServiceOptions {
    name = "multicaster";
    description = "Multicast repeater across L2 boundary";
    endpoints.mdns = {
      port = 5353;
      transport = "udp";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.${namespace}.multicaster;
    secrets.config = {
      file = "secrets/multicaster.toml";
      format = "binary";
      mountPath = configPath;
    };
    resources = {
      CPUQuota = "30%";
      MemoryMax = "128M";
      TasksMax = 256;
    };
    environment = {
      RUST_LOG = "info";
      TOKIO_WORKER_THREADS = "2";
    };
    serviceConfig.WorkingDirectory = configDirectory;
  });
}
