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
  cfg = config.${namespace}.hardware.spindown;
in
{
  options.${namespace}.hardware.spindown = with types; {
    enable = mkBoolOpt false "Whether or not to spin down hard disks on a schedule";
    disks = mkOpt (listOf str) [ ] "Disks to spin down, as /dev/disk/by-id paths";
    onCalendar = mkOpt str "*-*-* 05:00:00" "When to spin down the disks";
  };

  config = mkIf cfg.enable {
    systemd.services.spindown = {
      description = "Spin down hard disks";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = map (disk: "${pkgs.hdparm}/bin/hdparm -y ${disk}") cfg.disks;
      };
    };

    systemd.timers.spindown = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.onCalendar;
    };
  };
}
