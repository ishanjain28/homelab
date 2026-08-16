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
    monitor = {
      inherit (cfg) port;
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    name = "huawei-sms-telegram";
    description = "Huawei 5G Modem messages to Telegram";
    vlan = 50;
    secrets.env = {
      name = "huawei-sms-telegram";
      file = "secrets/huawei-sms-telegram.env";
      format = "dotenv";
      mountPath = containerSecretPath;
    };
    resources = {
      CPUQuota = "100%";
      MemoryMax = "128M";
      TasksMax = 256;
    };
    package = pkgs.${namespace}.huawei-sms-telegram;
    exec = "/bin/huawei-msg";
    environment = {
      RUST_LOG = "info";
    };
    serviceConfig = {
      EnvironmentFile = containerSecretPath;
    };
  });
}
