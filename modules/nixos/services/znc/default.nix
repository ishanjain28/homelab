{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.services.znc;
  configPath = "/run/container-secrets/znc.conf";
  certPath = "/run/container-secrets/znc.pem";
in
{
  options.${namespace}.services.znc = mkServiceOptions {
    name = "znc";
    endpoints = {
      irc.port = 40000;
      web.port = 25000;
    };
    monitor = enabled // {
      endpoint = "irc";
      protocol = "tcp";
    };
  };
  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    command = "${pkgs.znc}/bin/znc --foreground --datadir=/var/lib/znc";
    secrets = {
      config = {
        file = "secrets/znc/znc.conf";
        format = "binary";
        mountPath = configPath;
      };
      cert = {
        file = "secrets/znc/znc.pem";
        format = "binary";
        mountPath = certPath;
      };
    };
    serviceConfig = {
      StateDirectory = "znc";
      StateDirectoryMode = "0700";
      ExecStartPre = "${pkgs.writeShellScript "znc-config" ''
        mkdir -p /var/lib/znc/configs
        install -m 0600 ${configPath} /var/lib/znc/configs/znc.conf
      ''}";
    };
  });
}
