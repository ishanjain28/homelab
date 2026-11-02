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
  package = pkgs.copyparty.override { withFastThumbnails = true; };
  accountsPath = "/run/container-secrets/copyparty-accounts.conf";
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
      e2ts
      dedup
      zs
      zsl: https://share.ishanjain.me/
      og
      og-site: Ishan's Share
      og-ua: (?i)(discordbot|twitterbot|slackbot|telegrambot|whatsapp|redditbot|mastodon|synapse|googlebot)

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
    inherit package;
    command = "${package}/bin/copyparty -c ${accountsPath} -c ${configFile}";
    secrets.accounts = {
      file = "secrets/copyparty-accounts.conf";
      format = "binary";
      mountPath = accountsPath;
    };
    environment.XDG_CONFIG_HOME = "/var/lib/copyparty";
    serviceConfig.StateDirectory = "copyparty";
    resources = {
      CPUQuota = "200%";
      MemoryMax = "512M";
      TasksMax = 512;
    };
  });
}
