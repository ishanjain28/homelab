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
  probeSecretFiles = {
    ripe-atlas-primary = "secrets/ripe-atlas/primary.json";
    ripe-atlas-lte = "secrets/ripe-atlas/airtel.json";
  };
  spoolPath = "/var/lib/ripe-atlas/spool";
  spoolDirectories = [
    "data"
    "data/new"
    "data/oneoff"
    "data/out"
    "data/out/ooq"
    "data/out/ooq10"
    "crons"
    "crons/main"
  ]
  ++ map (number: "crons/${toString number}") (range 2 20);

  mkProbe =
    name: secretFile:
    let
      cfg = srv.${name};
      user = cfg.runtimeUser.name;
      group = cfg.runtimeUser.group;
      package = pkgs.${namespace}.ripe-atlas-software-probe.override {
        measurementUser = user;
        measurementGroup = group;
      };
    in
    mkIf cfg.enable (mkSingleServiceContainer {
      service = cfg;
      inherit package;
      exec = "/bin/ripe-atlas";
      secrets = {
        probe-key = {
          file = secretFile;
          format = "json";
          key = "private";
          mountPath = "/var/lib/ripe-atlas/probe_key";
        };
        probe-key-public = {
          file = secretFile;
          format = "json";
          key = "public";
          mountPath = "/var/lib/ripe-atlas/probe_key.pub";
        };
      };
      hardeningProfile = "network-monitor";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      resources = {
        CPUQuota = "100%";
        MemoryMax = "256M";
        TasksMax = 256;
      };
      environment.HOME = spoolPath;
      serviceConfig = {
        RuntimeDirectory = "ripe-atlas";
        StateDirectory = "ripe-atlas";
        StateDirectoryMode = "0700";
        WorkingDirectory = spoolPath;
        RestartSec = "10s";
      };
      containerConfig.systemd.tmpfiles.rules = [
        "L+ /var/lib/ripe-atlas/mode - - - - ${package}/share/ripe-atlas/defaults/mode"
        "d ${spoolPath} 2775 ${user} ${group} -"
      ]
      ++ map (directory: "d ${spoolPath}/${directory} 2775 ${user} ${group} -") spoolDirectories;
    });
in
{
  options.${namespace}.services = mapAttrs (
    name: _secretFile:
    mkServiceOptions {
      inherit name;
      description = "RIPE Atlas software probe";
      logging = disabled;
    }
  ) probeSecretFiles;

  config = mkMerge (mapAttrsToList mkProbe probeSecretFiles);
}
