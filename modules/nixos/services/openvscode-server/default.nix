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
  cfg = srv.openvscode-server;
  stateDir = "/var/lib/openvscode-server";
  connectionTokenPath = "/run/container-secrets/openvscode-server.token";
  hostNixUser = "openvscode-server-nix";
  hostNixUid = containerUidOffset + cfg.runtimeId;
  shellPackages = with pkgs; [
    bashInteractive
    coreutils
    curl
    fd
    file
    findutils
    fish
    git
    gnugrep
    gnused
    gnutar
    gzip
    jq
    less
    nano
    nix
    openssh
    ripgrep
    rsync
    unzip
    wget
    zip
  ];
in
{
  options.${namespace}.services.openvscode-server = mkServiceOptions {
    name = "openvscode-server";
    description = "OpenVSCode Server";
    endpoints.web.port = 3000;
    monitor = enabled // {
      endpoint = "web";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      users.groups.${hostNixUser}.gid = hostNixUid;
      users.users.${hostNixUser} = {
        isSystemUser = true;
        uid = hostNixUid;
        group = hostNixUser;
      };

      nix.settings.allowed-users = [ hostNixUser ];
    }

    (mkSingleServiceContainer {
      service = cfg;
      package = pkgs.openvscode-server;
      command = concatStringsSep " " [
        "${pkgs.openvscode-server}/bin/openvscode-server"
        "--accept-server-license-terms"
        "--host=0.0.0.0"
        "--port=${toString cfg.endpoints.web.port}"
        "--connection-token-file=${connectionTokenPath}"
        "--telemetry-level=off"
        "--user-data-dir=${stateDir}/user-data"
        "--server-data-dir=${stateDir}/server-data"
        "--extensions-dir=${stateDir}/extensions"
        "${stateDir}/workspace"
      ];

      secrets.connection-token = {
        file = "secrets/openvscode-server.token";
        format = "binary";
        mountPath = connectionTokenPath;
      };

      resources = {
        CPUQuota = "400%";
        MemoryMax = "4G";
        TasksMax = 1024;
      };

      environment = {
        HOME = stateDir;
        SHELL = "${pkgs.fish}/bin/fish";
      };

      serviceConfig = {
        StateDirectory = "openvscode-server";
        StateDirectoryMode = "0700";
      };

      containerConfig = {
        systemd.services.openvscode-server.path = shellPackages;

        environment.systemPackages = shellPackages;

        nix = mkForce enabled;
        programs.fish = enabled // {
          interactiveShellInit = fishKeyBindings;
        };
        programs.nix-ld = enabled;
        users.users.${cfg.runtimeUser.name}.shell = pkgs.bashInteractive;
      };
    })
  ]);
}
