{
  config,
  inputs,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.caddy;
  json = pkgs.formats.json { };
  fleetRegistry = inputs.self.lib.homelabRegistry;
  generatedConfig = mkIngressConfig {
    ingressName = cfg.ingressProvider.name;
    caddy = cfg;
    inherit (fleetRegistry) services;
  };
  generatedConfigFile = json.generate "caddy-${cfg.ingressProvider.name}.json" generatedConfig;
in
{
  options.${namespace}.services.caddy =
    mkServiceOptions {
      name = "caddy";
      description = "Caddy ingress proxy";
      endpoints = {
        http.port = 80;
        https.port = 443;
        admin = {
          port = 2019;
          expose = false;
        };
      };
      monitor = enabled // {
        endpoint = "https";
        protocol = "tcp";
      };
    }
    // {
      ingressProvider.name = mkOpt types.str "" "Logical ingress name provided by this Caddy instance.";

      settings =
        mkOpt types.attrs { }
          "Caddy-owned native JSON settings outside the generated service routes.";

      server = {
        name = mkOpt types.str "https" "Caddy HTTP server receiving generated service routes.";

        listen = mkOpt (types.nonEmptyListOf types.str) [
          ":443"
        ] "Addresses on which the generated Caddy server listens.";

        namedRoutes =
          mkOpt (types.attrsOf types.attrs) { }
            "Named Caddy routes available to invoke handlers in this server.";

        settings = mkOpt types.attrs { } "Caddy-owned settings merged into the generated HTTP server.";

        routes = {
          before =
            mkOpt (types.listOf types.attrs) [ ]
              "Ingress-wide Caddy routes emitted before all service routes.";
          after =
            mkOpt (types.listOf types.attrs) [ ]
              "Ingress-wide Caddy routes emitted after all service routes.";
        };
      };

      generatedConfigFile = mkOption {
        type = types.path;
        readOnly = true;
        default = generatedConfigFile;
        description = "Generated native Caddy JSON configuration for this ingress.";
      };
    };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.ingressProvider.name != "";
          message = "The Caddy service requires ingressProvider.name.";
        }
      ];
    }

    (mkSingleServiceContainer {
      service = cfg;
      command = "${pkgs.${namespace}.caddy}/bin/caddy run --config ${cfg.generatedConfigFile}";

      environment.XDG_DATA_HOME = "/var/lib";

      resources = {
        CPUQuota = "400%";
        MemoryMax = "1G";
        TasksMax = 1024;
      };

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
        StateDirectory = "caddy";
        StateDirectoryMode = "0700";
        UMask = "0077";
      };
    })
  ]);
}
