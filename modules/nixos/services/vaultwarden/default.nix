{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.services.vaultwarden;
  configFile = "/run/container-secrets/vaultwarden-config.json";
  rsaKey = "/run/container-secrets/vaultwarden-keys/rsa_key";
in
{
  options.${namespace}.services.vaultwarden = mkServiceOptions {
    name = "vaultwarden";
    endpoints.web.port = 8222;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/alive";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets = {
      config = {
        file = "secrets/vaultwarden/config.json";
        format = "json";
        mountPath = configFile;
      };
      rsa-key = {
        file = "secrets/vaultwarden/keys.json";
        format = "json";
        key = "rsa_key.pem";
        mountPath = "${rsaKey}.pem";
      };
      rsa-pub-key = {
        file = "secrets/vaultwarden/keys.json";
        format = "json";
        key = "rsa_key.pub.pem";
        mountPath = "${rsaKey}.pub.pem";
      };
    };
    containerConfig.services.vaultwarden = enabled // {
      dbBackend = "postgresql";
      config = {
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = cfg.endpoints.web.port;
        CONFIG_FILE = configFile;
        RSA_KEY_FILENAME = rsaKey;
        TZ = "Asia/Kolkata";
        LOG_LEVEL = "warn";
        EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "pm-32413-multi-client-password-management,ssh-agent-v2,pm-32009-new-item-types,pm-34171-card-scanner";
      };
    };
  });
}
