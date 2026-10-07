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
  cfg = srv.omada;
  package = pkgs.${namespace}.omada-controller;
in
{
  options.${namespace}.services.omada = mkServiceOptions {
    name = "omada";
    description = "TP-Link Omada Network Application";
    endpoints = {
      web-http.port = 8088;
      web-https.port = 8043;
      portal-https.port = 8843;
      olt-discovery = {
        port = 19810;
        transport = "udp";
      };
      app-discovery = {
        port = 27001;
        transport = "udp";
      };
      discovery = {
        port = 29810;
        transport = "udp";
      };
      manager-v1.port = 29811;
      adopt-v1.port = 29812;
      upgrade-v1.port = 29813;
      manager-v2.port = 29814;
      transfer-v2.port = 29815;
      rtty.port = 29816;
      device-monitor.port = 29817;
    };
    monitor = enabled // {
      endpoint = "web-https";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    serviceProfile = "jit";
    inherit package;
    exec = "/bin/omada-controller";
    containerTimeout = "3min";
    resources = {
      CPUQuota = "500%";
      MemoryMax = "5G";
      TasksMax = 1024;
    };

    containerConfig.systemd.services.omada.path = [
      pkgs.bash
      pkgs.procps
    ];

    serviceConfig = {
      StateDirectory = "omada";
      StateDirectoryMode = "0700";
      LimitNOFILE = 65536;
    };
  });
}
