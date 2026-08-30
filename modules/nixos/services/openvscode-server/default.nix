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
    port.number = 3000;
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.openvscode-server;
    command = concatStringsSep " " [
      "${pkgs.openvscode-server}/bin/openvscode-server"
      "--accept-server-license-terms"
      "--host=0.0.0.0"
      "--port=${toString cfg.port.number}"
      "--without-connection-token"
      "--telemetry-level=off"
      "--user-data-dir=${stateDir}/user-data"
      "--server-data-dir=${stateDir}/server-data"
      "--extensions-dir=${stateDir}/extensions"
      "${stateDir}/workspace"
    ];

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
      RestartSec = "5s";
    };

    containerConfig = {
      systemd.services.openvscode-server.path = shellPackages;

      environment.systemPackages = mkForce shellPackages;

      nix = mkForce enabled;
      users.users.${cfg.runtimeUser.name}.shell = pkgs.bashInteractive;
    };
  });
}
