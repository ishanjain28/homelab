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
    monitor = disabled;
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets = {
      asteriskConf = {
        file = "secrets/asterisk/asterisk.conf";
        format = "binary";
        mountPath = "/etc/asterisk/asterisk.conf";
      };
      cdrConf = {
        file = "secrets/asterisk/cdr.conf";
        format = "binary";
        mountPath = "/etc/asterisk/cdr.conf";
      };
      cdrCustomConf = {
        file = "secrets/asterisk/cdr_custom.conf";
        format = "binary";
        mountPath = "/etc/asterisk/cdr_custom.conf";
      };
      confbridgeConf = {
        file = "secrets/asterisk/confbridge.conf";
        format = "binary";
        mountPath = "/etc/asterisk/confbridge.conf";
      };
      dnsmgrConf = {
        file = "secrets/asterisk/dnsmgr.conf";
        format = "binary";
        mountPath = "/etc/asterisk/dnsmgr.conf";
      };
      extensionsConf = {
        file = "secrets/asterisk/extensions.conf";
        format = "binary";
        mountPath = "/etc/asterisk/extensions.conf";
      };
      indicationsConf = {
        file = "secrets/asterisk/indications.conf";
        format = "binary";
        mountPath = "/etc/asterisk/indications.conf";
      };
      loggerConf = {
        file = "secrets/asterisk/logger.conf";
        format = "binary";
        mountPath = "/etc/asterisk/logger.conf";
      };
      modulesConf = {
        file = "secrets/asterisk/modules.conf";
        format = "binary";
        mountPath = "/etc/asterisk/modules.conf";
      };
      musiconholdConf = {
        file = "secrets/asterisk/musiconhold.conf";
        format = "binary";
        mountPath = "/etc/asterisk/musiconhold.conf";
      };
      pjsipConf = {
        file = "secrets/asterisk/pjsip.conf";
        format = "binary";
        mountPath = "/etc/asterisk/pjsip.conf";
      };
      pjsipNotifyConf = {
        file = "secrets/asterisk/pjsip_notify.conf";
        format = "binary";
        mountPath = "/etc/asterisk/pjsip_notify.conf";
      };
      queuesConf = {
        file = "secrets/asterisk/queues.conf";
        format = "binary";
        mountPath = "/etc/asterisk/queues.conf";
      };
      resolverUnboundConf = {
        file = "secrets/asterisk/resolver_unbound.conf";
        format = "binary";
        mountPath = "/etc/asterisk/resolver_unbound.conf";
      };
      rtpConf = {
        file = "secrets/asterisk/rtp.conf";
        format = "binary";
        mountPath = "/etc/asterisk/rtp.conf";
      };
      voicemailConf = {
        file = "secrets/asterisk/voicemail.conf";
        format = "binary";
        mountPath = "/etc/asterisk/voicemail.conf";
      };
    };

    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 1024;
    };

    containerConfig = {
      services.asterisk = enabled // {
        package = pkgs.asterisk;
        useTheseDefaultConfFiles = [ ];
      };

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
