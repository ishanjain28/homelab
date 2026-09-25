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
  cfg = srv.adguardhome;
  secretConfigPath = "/run/container-secrets/adguardhome.yaml";
  stateDir = "/var/lib/adguardhome";
  configPath = "${stateDir}/AdGuardHome.yaml";
in
{
  options.${namespace}.services.adguardhome =
    mkServiceOptions {
      name = "adguardhome";
      description = "AdGuard Home DNS resolver";
      endpoints = {
        dns = {
          port = 53;
          transport = "tcp-and-udp";
        };
        tls = {
          port = 853;
          transport = "tcp-and-udp";
        };
        https.port = 8443;
        web = {
          port = 3000;
          expose = false;
        };
      };
      monitor = enabled // {
        endpoint = "dns";
        protocol = "tcp";
      };
    }
    // {
      configFile = mkOption {
        type = types.nonEmptyStr;
        description = "Repository-relative path to the encrypted AdGuardHome.yaml.";
      };
    };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    command = "${pkgs.adguardhome}/bin/AdGuardHome --no-check-update --config ${configPath} --work-dir ${stateDir}";
    hardeningProfile = "privileged-ports";

    secrets.config = {
      file = cfg.configFile;
      format = "yaml";
      mountPath = secretConfigPath;
    };

    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };

    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/install -m 0600 ${secretConfigPath} ${configPath}";
      StateDirectory = "adguardhome";
      StateDirectoryMode = "0700";
    };
  });
}
