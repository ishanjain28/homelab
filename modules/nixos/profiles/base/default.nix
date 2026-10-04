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

    environment.shellAliases = shellAliases;
    programs.fish = enabled;
    users.defaultUserShell = pkgs.fish;

    environment.shells = with pkgs; [
      bashInteractive
      fish
    ];

    environment.systemPackages =
      with pkgs;
      [
        gptfdisk
        pv
      ]
      ++ map (p: p.terminfo) [
        kitty
        alacritty
        ghostty
      ];

    documentation = disabled // {
      doc = disabled;
      dev = disabled;
      man = disabled;
    };
  };
}
