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
  cfg = config.${namespace}.profiles.base;
in
{
  options.${namespace}.profiles.base.enable = mkEnableOption "common NixOS defaults";

  config = mkIf cfg.enable {
    time.timeZone = timeZone;

    environment.enableAllTerminfo = true;
    environment.shellAliases = shellAliases;
    programs.fish = enabled;
    users.defaultUserShell = pkgs.fish;

    environment.shells = with pkgs; [
      bashInteractive
      fish
    ];

    documentation = disabled // {
      doc = disabled;
      dev = disabled;
      man = disabled;
    };
  };
}
