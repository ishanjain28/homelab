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
  cfg = srv.huawei-sms-telegram;
  containerSecretPath = "/run/container-secrets/huawei-sms-telegram.env";
in
{
  options.${namespace}.services.huawei-sms-telegram = mkServiceOptions {
    name = "huawei-sms-telegram";
    # No way to monitor it yet
    monitor = disabled;
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    name = "huawei-sms-telegram";
    description = "Huawei 5G Modem messages to Telegram";
    service = cfg;
    secrets.env = {
      file = "secrets/huawei-sms-telegram.env";
      format = "dotenv";
      mountPath = containerSecretPath;
    };
    resources = {
      CPUQuota = "30%";
      MemoryMax = "128M";
      TasksMax = 256;
    };
    package = pkgs.${namespace}.huawei-sms-telegram;
    exec = "/bin/huawei-msg";
    environment = {
      RUST_LOG = "info";
      TOKIO_WORKER_THREADS = "2";
    };
    serviceConfig = {
      EnvironmentFile = containerSecretPath;
    };
  });
}
