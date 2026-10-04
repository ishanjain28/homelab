{
  targets.local = {
    repository = "/var/lib/backups/restic";
    maintenance.onCalendar = "Sun 04:00";
  };

  targets.gdrive = {
    repository = "rclone:gdrive:homelab-backups/manaslu";
    maintenance = {
      onCalendar = "Sun 06:00";
      readDataSubset = "1%";
    };
  };

  groups = {
    hourly = {
      target = "local";
      onCalendar = "hourly";
      randomizedDelaySec = "5m";
      keep = {
        hourly = 48;
        daily = 14;
      };
    };

    offsite = {
      target = "gdrive";
      onCalendar = "*-*-* 03:00";
      randomizedDelaySec = "60m";
      keep = {
        daily = 7;
        weekly = 4;
        monthly = 12;
      };
    };
  };
}
