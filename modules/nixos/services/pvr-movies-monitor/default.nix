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
  cfg = srv.pvr-movies-monitor;
in
{
  options.${namespace}.services.pvr-movies-monitor = {
    enable = mkEnableOption "PVR Movies Monitor";
    host = mkOpt types.str "" "Listen address for this application";
    port = mkOpt types.str "" "Port to listen on";
    apiKey = mkOpt types.str "" "API Key for the application";
    volumeConfig = mkOpt attrs { } "Volume configuration";
  };

  config = mkIf cfg.enable (
    mkMerge (
      (attrValues cfg.volumeConfig)
      ++ [
        {
          # TODO: test vlans on real machine.
          #networking.vlans.vlan10 = {
          #  id = 10;
          #  interface = "br0";
          #};
          #networking.bridges.br0.interfaces = [ "ens18" ];

          containers.pvr-movies-monitor = {
            autoStart = true;
            privateNetwork = true;
            macvlans = [ "ens18" ];
            # macvlans = [ "vlan10" ];

            specialArgs = {
              inherit namespace;
              pvr-movies-monitor-package = pkgs.${namespace}.pvr-movies-monitor;
            };

            config =
              { pvr-movies-monitor-package, ... }:
              {
                # networking.useDHCP = true;
                networking.networkmanager.enable = false;
                networking.interfaces.mv-ens18.useDHCP = true;
                networking.firewall.allowedTCPPorts = [ 3000 ];

                environment.systemPackages = with pkgs; [
                  htop
                  ncdu
                  kitty.terminfo
                ];

                systemd.services.pvr-movies-monitor = {
                  description = "PVR Movies Monitoring Service";
                  wantedBy = [ "multi-user.target" ];
                  environment = {
                    API_KEY = cfg.apiKey;
                    HOST = cfg.host;
                    PORT = cfg.port;
                  };
                  serviceConfig = {
                    ExecStart = "${pvr-movies-monitor-package}/bin/pvr-movies-monitor";
                    Restart = "always";
                    DynamicUser = true;
                  };
                };

                system.stateVersion = "26.05";
              };
          };
        }
      ]
    )
  );
}
