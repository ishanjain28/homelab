{
  targets.local = {
    repository = "/var/lib/backups/restic";
    requiresMountsFor = [ "/var/lib/backups" ];
    maintenance.onCalendar = "Sun 00:30";
  };

  targets.gdrive = {
    repository = "rclone:gdrive:kepler";
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

    daily = {
      target = "local";
      onCalendar = "*-*-* 03:00";
      randomizedDelaySec = "30m";
      keep = {
        last = 3;
        daily = 14;
        weekly = 8;
        monthly = 6;
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
    offsite-weekly = {
      target = "gdrive";
      onCalendar = "Sun 03:00";
      randomizedDelaySec = "60m";
      keep = {
        weekly = 8;
        monthly = 12;
      };
    };
  };
}
