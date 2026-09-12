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
  labels = [ "ubuntu-latest:docker://gitea/runner-images:ubuntu-latest" ];
in
{
  options.${namespace}.services.gitea-runner =
    mkServiceOptions {
      name = "gitea-runner";
      description = "Gitea Actions runner";
    }
    // {
      giteaURI = mkOption {
        type = types.nonEmptyStr;
        description = "Gitea instance URI.";
      };
    };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;

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
      # Docker exists only inside this unprivileged service container.
      # network=host below therefore means the runner container's VLAN 50
      # namespace, not Kepler's host network namespace.
      virtualisation.docker = enabled // {
        extraPackages = [ pkgs.nftables ];
      };

      services.gitea-actions-runner.instances.${instanceName} = enabled // {
        name = instanceName;
        url = cfg.giteaURI;
        tokenFile = runnerEnv;
        inherit labels;

        settings = {
          log.level = "info";

          runner = {
            file = ".runner";
            capacity = 1;
            env_file = ".env";
            timeout = "3h";
            shutdown_timeout = "0s";
            insecure = false;
            fetch_timeout = "5s";
            fetch_interval = "2s";
            inherit labels;
          };

          cache = {
            enabled = true;
            dir = "";
            host = "";
            port = 0;
            external_server = "";
          };

          container = {
            network = "host";
            privileged = false;
            options = null;
            workdir_parent = null;
            valid_volumes = [ ];
            docker_host = "";
            force_pull = true;
            force_rebuild = false;
          };

          host.workdir_parent = null;
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
        UMask = "0077";
      };
    };
  });
}
