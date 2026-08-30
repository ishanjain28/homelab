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
  cfg = srv.changedetection;
  browserPort = 3000;
  datastorePath = "/var/lib/changedetection-io";
  chromiumPath = "${datastorePath}/chromium";
  changedetectionPackage = pkgs.changedetection-io.overrideAttrs (old: {
    meta = old.meta // {
      # The pinned 0.53.6 release is Apache-2.0; nixpkgs still marks it unfree.
      license = licenses.asl20;
    };
  });
in
{
  options.${namespace}.services.changedetection = mkServiceOptions {
    name = "changedetection";
    port = 5000;
    monitor = {
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    name = "changedetection";
    service = cfg;
    ports = [ cfg.port ];
    resources = {
      CPUQuota = "400%";
      MemoryMax = "4G";
      TasksMax = 1024;
    };

    containerConfig = {
      services.changedetection-io = enabled // {
        package = changedetectionPackage;
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
        listenAddress = "0.0.0.0";
        inherit (cfg) port;
        inherit datastorePath;
        playwrightSupport = false;
        webDriverSupport = false;
      };

      systemd.services.changedetection-io = {
        after = [ "browserless.service" ];
        requires = [ "browserless.service" ];
        environment = {
          ALLOW_IANA_RESTRICTED_ADDRESSES = "true";
          DEFAULT_FETCH_BACKEND = "html_webdriver";
          HOME = datastorePath;
          PLAYWRIGHT_DRIVER_URL = "ws://127.0.0.1:${toString browserPort}/?stealth=1&--disable-web-security=true&--disable-crashpad=true&--disable-crash-reporter=true&--crash-dumps-dir=${chromiumPath}/crashes";
        };
        serviceConfig = {
          Restart = mkForce "always";
          RestartSec = "10s";
          StateDirectoryMode = mkForce "0700";
        };
      };

      systemd.services.browserless = {
        description = "Browserless Chromium service";
        wantedBy = [ "multi-user.target" ];
        before = [ "changedetection-io.service" ];
        after = [ "network.target" ];
        environment = {
          APP_DIR = "${pkgs.${namespace}.browserless}/lib/node_modules/browserless-chrome";
          CHROME_BINARY_LOCATION = "${pkgs.chromium}/bin/chromium";
          CONNECTION_TIMEOUT = "60000";
          HOST = "127.0.0.1";
          LANG = "C.UTF-8";
          NODE_ENV = "production";
          HOME = chromiumPath;
          PORT = toString browserPort;
          XDG_CACHE_HOME = "${chromiumPath}/cache";
          XDG_CONFIG_HOME = "${chromiumPath}/config";
          WORKSPACE_DIR = "/run/browserless";
        };
        serviceConfig = {
          ExecStart = "${pkgs.${namespace}.browserless}/bin/browserless";
          Restart = "always";
          RestartSec = "10s";
          RuntimeDirectory = "browserless";
          RuntimeDirectoryMode = "0700";
          User = cfg.runtimeUser.name;
          Group = cfg.runtimeUser.group;
          AmbientCapabilities = "";
          CapabilityBoundingSet = "";
          NoNewPrivileges = true;
          PrivateTmp = true;
          UMask = "0077";
        };
      };
    };
  });
}
