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
  containerEnvPath = "/run/container-secrets/lldap.env";
  containerKeyPath = "/run/container-secrets/lldap-server-key";
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
      ldapBaseDn = mkOpt str "dc=home,dc=arpa" "LLDAP base DN.";
      httpUrl = mkOpt str "http://localhost:17170" "LLDAP public URL.";
      ldapUserEmail = mkOpt str "admin@example.com" "Initial admin email.";
    });

  config = mkIf cfg.enable (mkSingleServiceContainer {
    name = "lldap";
    description = "LDAP server";
    inherit (cfg) vlan;
    ports = [
      cfg.ldapPort
      cfg.httpPort
    ];
    package = pkgs.lldap;
    exec = "/bin/lldap run";
    secrets = {
      env = {
        name = "lldap-env";
        file = "secrets/lldap/env.env";
        format = "dotenv";
        mountPath = containerEnvPath;
      };
      serverKey = {
        name = "lldap-server-key";
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
      LLDAP_LDAP_HOST = "0.0.0.0";
      LLDAP_LDAP_PORT = toString cfg.ldapPort;
      LLDAP_HTTP_HOST = "0.0.0.0";
      LLDAP_HTTP_PORT = toString cfg.httpPort;
      LLDAP_HTTP_URL = cfg.httpUrl;
      LLDAP_LDAP_BASE_DN = cfg.ldapBaseDn;
      LLDAP_LDAP_USER_EMAIL = cfg.ldapUserEmail;
      LLDAP_KEY_FILE = containerKeyPath;
    };

    serviceConfig = {
      EnvironmentFile = containerEnvPath;
      Restart = "always";
      RestartSec = "5s";

      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
    };
  });
}
