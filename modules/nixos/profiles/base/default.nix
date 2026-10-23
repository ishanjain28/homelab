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

    services.resolved.settings.Resolve.DNSStubListener = false;

    environment.shellAliases = shellAliases;
    services.lldpd = enabled;
    programs.fish = enabled // {
      interactiveShellInit = fishKeyBindings + ''
        ${getExe pkgs.atuin} init fish | source
      '';
    };
    programs.bash.interactiveShellInit = ''
      source ${pkgs.bash-preexec}/share/bash/bash-preexec.sh
      eval "$(${getExe pkgs.atuin} init bash)"
    '';
    environment.variables.ATUIN_CONFIG_DIR = "/etc/atuin";
    environment.etc."atuin/config.toml".text = "update_check = false\n";
    users.defaultUserShell = pkgs.fish;

    environment.shells = with pkgs; [
      bashInteractive
      fish
    ];

    environment.systemPackages =
      with pkgs;
      [
        atuin
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
