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
  cfg = srv.cups;
  printerDriver = pkgs.epson-escpr.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      ppd="$out/share/cups/model/epson-inkjet-printer-escpr/Epson-M205_Series-epson-escpr-en.ppd"
      substituteInPlace "$ppd" \
        --replace-fail '*ColorDevice:           True' '*ColorDevice:           False' \
        --replace-fail '*DefaultColorSpace:     RGB' '*DefaultColorSpace:     Gray' \
        --replace-fail '*Throughput:            "1"' '*Throughput:            "15"'
    '';
  });
  airscanConfig = pkgs.writeTextDir "etc/sane.d/airscan.conf" ''
    [devices]

    [options]
    discovery = enable
    protocol = auto
    ws-discovery = fast
    pretend-local = true
  '';
in
{
  options.${namespace}.services.cups = mkServiceOptions {
    name = "cups";
    description = "CUPS print and scan server";
    endpoints = {
      ipp.port = 631;
      sane.port = 6566;
      mdns = {
        port = 5353;
        transport = "udp";
      };
    };
    monitor = enabled // {
      endpoint = "ipp";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    resources = {
      CPUQuota = "400%";
      MemoryMax = "2G";
      TasksMax = 1024;
    };

    containerConfig = {
      services.printing = enabled // {
        drivers = [ printerDriver ];
        listenAddresses = [ "*:631" ];
        allowFrom = [ "all" ];
        startWhenNeeded = false;
        browsing = true;
        logLevel = "warn";
        browsed.enable = false;

        extraConf = ''
          ServerAlias *
          DefaultPaperSize A4
          BrowseDNSSDSubTypes _cups,_print,_universal
          ErrorPolicy abort-job
          PreserveJobFiles 31536000
          PreserveJobHistory 31536000
          MaxJobs 5000
          ServerTokens ProductOnly
          DefaultPolicy visible-jobs

          <Policy visible-jobs>
            JobPrivateAccess all
            JobPrivateValues none

            <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Current-Job Suspend-Current-Job Resume-Job CUPS-Move-Job>
              Require user @OWNER @SYSTEM
              Order deny,allow
            </Limit>

            <Limit Pause-Printer Resume-Printer Set-Printer-Attributes Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs Deactivate-Printer Activate-Printer Restart-Printer Shutdown-Printer Startup-Printer Promote-Job Schedule-Job-After CUPS-Add-Printer CUPS-Delete-Printer CUPS-Add-Class CUPS-Delete-Class CUPS-Accept-Jobs CUPS-Reject-Jobs CUPS-Set-Default>
              AuthType Basic
              Require user @SYSTEM
              Order deny,allow
            </Limit>

            <Limit Cancel-Job CUPS-Authenticate-Job>
              Require user @OWNER @SYSTEM
              Order deny,allow
            </Limit>

            <Limit All>
              Order deny,allow
            </Limit>
          </Policy>
        '';

        extraFilesConf = ''
          CacheDir /var/lib/cups/cache
          RequestRoot /var/lib/cups/spool
        '';
      };

      hardware.printers = {
        ensureDefaultPrinter = "EpsonM205";
        ensurePrinters = [
          {
            name = "EpsonM205";
            description = "Epson";
            location = "Home";
            deviceUri = "socket://10.0.70.14:9100";
            model = "epson-inkjet-printer-escpr/Epson-M205_Series-epson-escpr-en.ppd";
            ppdOptions = {
              PageSize = "A4";
              MediaType = "PLAIN_NORMAL";
              Ink = "MONO";
              "printer-error-policy" = "abort-job";
              "printer-is-shared" = "true";
              "printer-op-policy" = "visible-jobs";
            };
          }
        ];
      };

      hardware.sane = {
        extraBackends = [
          pkgs.sane-airscan
          airscanConfig
        ];
      };

      services.saned = enabled // {
        # Network policy is enforced between VLANs by the router.
        extraConfig = "+";
      };

      services.avahi = enabled // {
        openFirewall = false;
        publish = enabled // {
          userServices = true;
        };
      };

      # Avahi is Type=dbus. Starting it concurrently with dbus-broker can leave
      # the unit activating even after Avahi has finished starting, which keeps
      # the container from reaching multi-user.target.
      systemd.services.avahi-daemon = {
        after = [ "dbus.service" ];
        requires = [ "dbus.service" ];
      };

      services.resolved.settings.Resolve.MulticastDNS = false;
    };
  });
}
