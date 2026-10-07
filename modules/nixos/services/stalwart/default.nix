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
  cfg = config.${namespace}.services.stalwart;
  stateDir = "/var/lib/stalwart";
in
{
  options.${namespace}.services.stalwart = mkServiceOptions {
    name = "stalwart";
    description = "Stalwart mail server";
    endpoints = {
      smtp.port = 25;
      imaps.port = 993;
      http.port = 8080;
    };
    monitor = enabled // {
      endpoint = "smtp";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    command = "${pkgs.stalwart_0_16}/bin/stalwart --config ${stateDir}/config.json";
    serviceProfile = "privileged-ports";
    containerConfig.environment.systemPackages = [ pkgs.stalwart-cli ];
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };
    serviceConfig = {
      StateDirectory = "stalwart";
      StateDirectoryMode = "0700";
      WorkingDirectory = stateDir;
    };
  });
}
