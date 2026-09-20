{
  targets.nas = {
    repository = "/main/backups/restic";
    passwordSecret = "secrets/backups/nas.password";
    requiresMountsFor = [ "/main/backups" ];
    maintenance = {
      onCalendar = "Sun 04:00";
      readDataSubset = "5%";
    };
  };

  groups = {
    hourly = {
      target = "nas";
      onCalendar = "hourly";
      randomizedDelaySec = "5m";
      keep = {
        hourly = 48;
        daily = 14;
      };
    };

    daily = {
      target = "nas";
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
