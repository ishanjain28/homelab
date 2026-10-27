{
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.gitea-runner;
  runnerEnv = "/run/container-secrets/gitea-runner.env";
  instanceName = config.networking.hostName;
  labels = [ "nixos:host" ];
in
{
  options.${namespace}.services.gitea-runner =
    mkServiceOptions {
      name = "gitea-runner";
      description = "Gitea Actions runner";
      monitor = enabled // {
        protocol = "icmp";
      };
    }
    // {
      giteaURI = mkOption {
        type = types.nonEmptyStr;
        description = "Gitea instance URI.";
      };
    };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    serviceProfiles."gitea-runner-${instanceName}" = "jit";

    secrets.token = {
      file = "secrets/gitea-runner.env";
      format = "dotenv";
      mountPath = runnerEnv;
    };

    resources = {
      CPUQuota = "600%";
      MemoryMax = "12G";
      TasksMax = 8192;
    };

    containerConfig = {
      services.gitea-actions-runner.instances.${instanceName} = enabled // {
        name = instanceName;
        url = cfg.giteaURI;
        tokenFile = runnerEnv;
        inherit labels;

        hostPackages = with pkgs; [
          age
          bash
          coreutils
          curl
          diffutils
          dnscontrol
          findutils
          gawk
          git
          gnugrep
          gnused
          gnutar
          gzip
          jq
          nodejs
          wget
          xz
        ];

        settings = {
          log.level = "info";

          runner = {
            file = ".runner";
            capacity = 1;
            timeout = "3h";
            shutdown_timeout = "0s";
            insecure = false;
            fetch_timeout = "5s";
            fetch_interval = "2s";
            inherit labels;
          };

          cache.enabled = false;
        };
      };

      systemd.services."gitea-runner-${instanceName}".serviceConfig = {
        DynamicUser = mkForce false;
        User = cfg.runtimeUser.name;
        Group = cfg.runtimeUser.group;
        Restart = mkForce "always";
        RestartSec = mkForce "10s";
        StateDirectoryMode = "0700";
        TimeoutStartSec = "infinity";
        TimeoutStopSec = "infinity";
      };
    };
  });
}
