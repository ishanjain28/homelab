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
  srv = config.${namespace}.services;
  cfg = srv.pvr-movies-monitor;
in
{
  options.${namespace}.services.pvr-movies-monitor = {
    enable = mkEnableOption "PVR Movies Monitor";
    host = mkOpt types.str "" "Listen address for this application";
    port = mkOpt types.str "" "Port to listen on";
    apiKey = mkOpt types.str "" "API Key for the application";
  };

  config = mkIf cfg.enable {
    systemd.services.pvr-movies-monitor = {
      description = "PVR Movies Monitoring Service";
      wantedBy = [ "multi-user.target" ];
      environment = {
        API_KEY = cfg.apiKey;
        HOST = cfg.host;
        PORT = cfg.port;
      };
      serviceConfig = {
        ExecStart = "${pkgs.${namespace}.pvr-movies-monitor}/bin/pvr-movies-monitor";
        Restart = "always";
        DynamicUser = true;
      };
    };
  };
}
