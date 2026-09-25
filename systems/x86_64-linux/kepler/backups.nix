{
  targets.local = {
    repository = "/var/lib/backups/restic";
    passwordSecret = "secrets/backups/restic.password";
    requiresMountsFor = [ "/var/lib/backups" ];
    maintenance.onCalendar = "Sun 04:00";
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
  };
}
