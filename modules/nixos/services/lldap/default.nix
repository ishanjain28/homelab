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
  cfg = srv.lldap;
  confPath = "/run/container-secrets/config.toml";
  containerKeyPath = "/run/container-secrets/server-key";
in
{
  options.${namespace}.services.lldap =
    mkServiceOptions {
      name = "lldap";
      monitor = {
        port = cfg.httpPort;
        protocol = "http";
      };
    }
    // (with types; {
      ldapPort = mkOpt port 389 "LLDAP LDAP listener port.";
      httpPort = mkOpt port 17170 "LLDAP HTTP listener port.";
    });

  config = mkIf cfg.enable (mkSingleServiceContainer {
    name = "lldap";
    description = "LDAP server";
    service = cfg;
    ports = [
      cfg.ldapPort
      cfg.httpPort
    ];
    package = pkgs.lldap;
    exec = "/bin/lldap run -c ${confPath}";
    secrets = {
      env = {
        file = "secrets/lldap/config.toml";
        format = "binary";
        mountPath = confPath;
      };
      server-key = {
        file = "secrets/lldap/server.key";
        format = "binary";
        mountPath = containerKeyPath;
      };
    };
    resources = {
      CPUQuota = "100%";
      MemoryMax = "512M";
      TasksMax = 256;
    };

    environment = {
      LLDAP_KEY_FILE = containerKeyPath;
    };

    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";

      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
    };
  });
}
