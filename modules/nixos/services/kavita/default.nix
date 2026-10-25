{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.services.kavita;
  settingsPath = "/run/container-secrets/kavita-appsettings.json";
in
{
  options.${namespace}.services.kavita = mkServiceOptions {
    name = "kavita";
    description = "Kavita ebook library";
    endpoints.web.port = 5000;
    monitor = enabled // {
      endpoint = "web";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets.settings = {
      file = "secrets/kavita/appsettings.json";
      format = "json";
      mountPath = settingsPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };
    containerConfig = {
      services.kavita = enabled // {
        tokenKeyFile = settingsPath;
      };

      systemd.services.kavita.preStart = mkForce "install -m600 ${settingsPath} /var/lib/kavita/config/appsettings.json";
    };
  });
}
