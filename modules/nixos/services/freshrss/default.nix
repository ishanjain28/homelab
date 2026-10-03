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
  cfg = config.${namespace}.services.freshrss;
  passwordPath = "/run/container-secrets/freshrss-password";
  virtualHost = "http://:${toString cfg.endpoints.web.port}";

  inherit (pkgs.freshrss-extensions) buildFreshRssExtension;
  officialExtensions = pkgs.fetchFromGitHub {
    owner = "FreshRSS";
    repo = "Extensions";
    rev = "3ee24369b7c3eda3a4222c2b5eb5446a0b4328b8";
    hash = "sha256-P1YpObJVTmgMYk21buPMhHZHGmyGnEA1M3KMsMSvdAI=";
  };
  extensions = with pkgs.freshrss-extensions; [
    reading-time
    reddit-image
    (buildFreshRssExtension {
      FreshRssExtUniqueId = "ImageProxy";
      pname = "image-proxy";
      version = "1.0.1";
      src = officialExtensions;
      sourceRoot = "${officialExtensions.name}/xExtension-ImageProxy";
    })
    (buildFreshRssExtension rec {
      FreshRssExtUniqueId = "LatexSupport";
      pname = "latex-support";
      version = "0.1.5";
      src = pkgs.fetchFromGitHub {
        owner = "aledeg";
        repo = "xExtension-LatexSupport";
        rev = version;
        hash = "sha256-DvL5tyj0FHVCL9ZcBSLuZ01shB448WDVpQmgkYLhoLs=";
      };
    })
  ];
in
{
  options.${namespace}.services.freshrss =
    mkServiceOptions {
      name = "freshrss";
      endpoints.web.port = 8081;
      monitor = enabled // {
        endpoint = "web";
        protocol = "tcp";
      };
    }
    // {
      baseUrl = mkOption { type = types.str; };
    };
  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets.password = {
      file = "secrets/freshrss-password";
      format = "binary";
      mountPath = passwordPath;
    };
    containerConfig = {
      services.freshrss = {
        enable = true;
        inherit (cfg) baseUrl;
        defaultUser = "ishan";
        inherit extensions;
        passwordFile = passwordPath;
        webserver = "caddy";
        inherit virtualHost;
        database = {
          type = "pgsql";
          host = "localhost";
          port = 5432;
          inherit (cfg.database) name;
          user = cfg.database.name;
        };
      };
      services.caddy = {
        globalConfig = "admin off";
        enableReload = false;
        virtualHosts.${virtualHost}.listenAddresses = [ "127.0.0.1" ];
      };
    };
  });
}
