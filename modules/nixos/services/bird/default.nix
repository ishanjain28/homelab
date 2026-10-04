{
  config,
  inputs,
  lib,
  pkgs,
  namespace,
  ...
}:
let
  cfg = config.${namespace}.services.bird;
  secret = config.sops.secrets.bird-config;
in
{
  options.${namespace}.services.bird = with lib; {
    enable = mkEnableOption "BIRD BGP routing daemon";
    package = mkPackageOption pkgs "bird3" { };
    passwordSecret = mkOption {
      type = types.nonEmptyStr;
      default = "secrets/bird.password";
      description = "Repository-relative SOPS file included before the config; it defines `password`.";
    };
    config = mkOption {
      type = types.lines;
      description = "BIRD configuration. passwordSecret is included first and defines `password`.";
    };
  };
  config = lib.mkIf cfg.enable {
    sops.secrets.bird-config = {
      sopsFile = "${inputs.self}/${cfg.passwordSecret}";
      format = "binary";
      owner = "bird";
      group = "bird";
      mode = "0400";
      restartUnits = [ "bird.service" ];
    };
    services.bird = {
      enable = true;
      inherit (cfg) package;
      config = ''
        include "${secret.path}";
        ${cfg.config}
      '';
      checkConfig = false;
    };
  };
}
