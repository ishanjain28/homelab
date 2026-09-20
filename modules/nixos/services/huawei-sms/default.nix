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
  cfg = srv.huawei-sms;
  containerSecretPath = "/run/container-secrets/huawei-sms.env";
in
{
  options.${namespace}.services.huawei-sms = mkServiceOptions {
    name = "huawei-sms";
    description = "Huawei 5G Modem messages to Pushover";
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    secrets.env = {
      file = "secrets/huawei-sms.env";
      format = "dotenv";
      mountPath = containerSecretPath;
    };
    resources = {
      CPUQuota = "30%";
      MemoryMax = "128M";
      TasksMax = 256;
    };
    package = pkgs.${namespace}.huawei-sms;
    environment = {
      RUST_LOG = "warn";
      TOKIO_WORKER_THREADS = "2";
      STATE_FILE = "/var/lib/huawei-sms/state.json";
    };
    serviceConfig = {
      EnvironmentFile = containerSecretPath;
      StateDirectory = "huawei-sms";
    };
  });
}
