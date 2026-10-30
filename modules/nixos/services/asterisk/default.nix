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
  cfg = srv.asterisk;
in
{
  options.${namespace}.services.asterisk = mkServiceOptions {
    name = "asterisk";
    description = "Asterisk SIP PBX";
    endpoints = {
      sip-udp = {
        port = 5060;
        transport = "udp";
      };
      sip-tcp.port = 5060;
      sip-tls.port = 5061;
    };
    monitor = enabled // {
      endpoint = "sip-tcp";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets =
      genAttrs
        [
          "cdr"
          "cdr_custom"
          "confbridge"
          "dnsmgr"
          "extensions"
          "indications"
          "logger"
          "modules"
          "musiconhold"
          "pjsip"
          "pjsip_jio"
          "pjsip_notify"
          "queues"
          "resolver_unbound"
          "rtp"
          "voicemail"
        ]
        (name: {
          file = "secrets/asterisk/${name}.conf";
          format = "binary";
          mountPath = "/etc/asterisk/${name}.conf";
        });

    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 1024;
    };

    containerConfig = {
      services.asterisk = enabled // {
        package = pkgs.${namespace}.asterisk-jio;
        useTheseDefaultConfFiles = [ ];
        extraConfig = "astdatadir => ${pkgs.asterisk}/var/lib/asterisk";
      };

      networking.firewall.rejectPackets = true;

      networking.firewall.allowedUDPPortRanges = [
        {
          from = 10000;
          to = 20000;
        }
        {
          # Keep this in sync with secrets/asterisk/rtp.conf.
          from = 52000;
          to = 52200;
        }
      ];
    };
  });
}
