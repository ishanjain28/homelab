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
  secret = config.sops.secrets.huawei-sms-telegram;
in
{
  options.${namespace}.services.huawei-sms-telegram = mkServiceOptions {
    name = "huawei-sms-telegram";
    monitor = {
      inherit (cfg) port;
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      sops.secrets.huawei-sms-telegram = {
        sopsFile = snowfall.fs.get-file "secrets/huawei-sms-telegram.env";
        format = "dotenv";
        restartUnits = [ "container@huawei-sms-telegram.service" ];
      };

      containers.huawei-sms-telegram = {
        bindMounts.${secret.path} = {
          hostPath = secret.path;
          isReadOnly = true;
        };
      };
    }

    (mkNspawnService {
      name = "huawei-sms-telegram";
      description = "Huawei 5G Modem messages to Telegram";
      vlan = 50;
      package = pkgs.${namespace}.huawei-sms-telegram;
      exec = "/bin/huawei-msg";
      environment = {
        RUST_LOG = "info";
      };
      serviceConfig = {
        EnvironmentFile = secret.path;
      };
    })
  ]);
}
