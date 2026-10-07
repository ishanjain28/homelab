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
    enable = mkBoolOpt false "Whether or not to spin down idle hard disks";
    disks = mkOpt (listOf str) [ ] "Disks to spin down, as /dev/disk/by-id paths";
    idleTime = mkOpt int 1800 "Seconds without IO before a disk is spun down";
    onCalendar = mkOpt str "*-*-* 05:00:00" "When to spin down all disks immediately";
  };

  config = mkIf cfg.enable {
    systemd.services.hd-idle = {
      description = "Spin down idle hard disks";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hd-idle}/bin/hd-idle -i 0 -c ata ${
          concatMapStringsSep " " (disk: "-a ${disk} -i ${toString cfg.idleTime}") cfg.disks
        }";
        Restart = "always";
      };
    };

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
