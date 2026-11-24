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
  cfg = config.${namespace}.services.home-assistant;
in
{
  options.${namespace}.services.home-assistant = mkServiceOptions {
    name = "home-assistant";
    description = "Home Assistant";
    endpoints.web.port = 8123;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      ${namespace}.services.home-assistant.runtimeUser = {
        name = mkDefault "hass";
        group = mkDefault "hass";
      };
    }

    (mkServiceContainer {
      service = cfg;
      secrets.config = {
        file = "secrets/home-assistant/configuration.yaml";
        format = "yaml";
        mountPath = "/var/lib/hass/configuration.yaml";
      };
      resources = {
        CPUQuota = "200%";
        MemoryMax = "2G";
        TasksMax = 1024;
      };
      containerConfig = {
        services.home-assistant = {
          enable = true;
          customComponents = with pkgs.home-assistant-custom-components; [
            auth_oidc
            tuya_local
          ];
          extraPackages = ps: [ ps.psycopg2 ];
          extraArgs = [ "--log-no-color" ];
          config = null;
        };
        systemd.services.home-assistant.environment.HA_DISABLE_LOG_FILE = "1";
      };
    })
  ]);
}
