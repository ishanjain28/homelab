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
  cfg = config.${namespace}.services.copyparty;
  dataDir = "/srv/copyparty";
  configFile = pkgs.writeText "copyparty.conf" ''
    [global]
      i: ::
      p: ${toString cfg.endpoints.web.port}
      http-only
      rproxy: 1
      xff-hdr: x-forwarded-for
      xff-src: ${mkIpv6Address "caddy" 50}/128
      idp-h-usr: remote-user
      idp-h-grp: remote-groups
      shr: /shr
      e2d
      zs
      zsl: https://transfer.ishanjain.me/

    [/]
      ${dataDir}
      accs:
        rwmd: @acct
        A: @transfer-admin
  '';
in
{
  options.${namespace}.services.copyparty = mkServiceOptions {
    name = "copyparty";
    description = "Copyparty file transfer";
    endpoints = {
      web.port = 3923;
      ssdp = {
        port = 1900;
        transport = "udp";
      };
    };
    monitor = enabled // {
      endpoint = "web";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.copyparty;
    command = "${pkgs.copyparty}/bin/copyparty -c ${configFile}";
    environment.XDG_CONFIG_HOME = "/var/lib/copyparty";
    serviceConfig.StateDirectory = "copyparty";
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };
  });
}
