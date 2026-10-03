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
    config = mkOption {
      type = types.lines;
      description = "BIRD configuration. secrets/bird.password is included first and defines `vultr_password`.";
    };
  };
  config = lib.mkIf cfg.enable {
    sops.secrets.bird-config = {
      sopsFile = "${inputs.self}/secrets/bird.password";
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
