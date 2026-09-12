{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.nitter;
  configPath = "/run/container-secrets/nitter.conf";
  sessionsPath = "/run/container-secrets/nitter-sessions.jsonl";
in
{
  options.${namespace}.services.nitter = mkServiceOptions {
    name = "nitter";
    description = "Nitter frontend for Twitter";
    endpoints.web.port = 8080;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets.config = {
      file = "secrets/nitter/nitter.conf";
      format = "binary";
      mountPath = configPath;
    };
    secrets.sessions = {
      file = "secrets/nitter/sessions.jsonl";
      format = "binary";
      mountPath = sessionsPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "512M";
      TasksMax = 256;
    };

    containerConfig = {
      services.nitter = enabled // {
        openFirewall = false;
        sessionsFile = sessionsPath;
        redisCreateLocally = true;
        server = {
          address = "0.0.0.0";
          port = cfg.endpoints.web.port;
          https = true;
        };
      };

      systemd.services.nitter.serviceConfig = {
        DynamicUser = mkForce false;
        User = cfg.runtimeUser.name;
        Group = cfg.runtimeUser.group;
        Environment = mkForce [
          "NITTER_CONF_FILE=${configPath}"
          "NITTER_SESSIONS_FILE=${sessionsPath}"
        ];
        StateDirectoryMode = "0700";
      };
    };
  });
}
