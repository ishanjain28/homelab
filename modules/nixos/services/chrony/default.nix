{ config, lib, namespace, ... }:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.chrony;
in {
  options.${namespace}.services.chrony = {
    enable = mkEnableOption "Chrony: NTP Client & Server";
  };

  config = mkIf cfg.enable {
    services.chrony = enabled // {
      enableRTCTrimming = false;
      extraConfig = ''
        makestep 1.0 3
        driftfile /var/lib/chrony/drift
      '';
      servers = [ "time.cloudflare.com" "time.google.com" "time.windows.com" ];
    };
  };
}
