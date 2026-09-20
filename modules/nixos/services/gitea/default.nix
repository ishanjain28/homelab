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
  cfg = srv.gitea;
  confPath = "/run/container-secrets/app.ini";
  workDir = "/var/lib/gitea";
in
{
  options.${namespace}.services.gitea = mkServiceOptions {
    name = "gitea";
    description = "Gitea git hosting";
    endpoints = {
      web.port = 3000;
      ssh.port = 2222;
    };
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/api/healthz";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.gitea;
    exec = "/bin/gitea web --config ${confPath}";

    secrets.config = {
      file = "secrets/gitea.config";
      format = "binary";
      mountPath = confPath;
    };

    resources = {
      CPUQuota = "800%";
      MemoryMax = "4G";
      TasksMax = 2048;
    };

    environment = {
      HOME = workDir;
      USER = cfg.runtimeUser.name;
      GITEA_WORK_DIR = workDir;
      GITEA_CUSTOM = "${workDir}/custom";
    };

    serviceConfig = {
      StateDirectory = "gitea";
      StateDirectoryMode = "0700";
      WorkingDirectory = workDir;
    };
  });
}
