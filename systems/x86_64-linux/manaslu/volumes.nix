{
  postgresql-del-primary = {
    uuid = "3ab2c243-fc4f-436d-8fcd-fc6207008209";
    mountPath = "/var/lib/postgresql";
    size = "2G";
    backup.groups = [
      "hourly"
      "offsite"
    ];
  };

  vaultwarden = {
    uuid = "47f65af3-efad-4a8c-9853-b39f7b74510b";
    size = "1G";
    backup.groups = [ "offsite" ];
  };

  freshrss = {
    uuid = "c60d79c3-9ae1-4f8d-9e2f-0e04a3bd2e04";
    size = "1G";
    backup.groups = [ "offsite" ];
  };

  znc = {
    uuid = "1481173f-88ff-4a3d-8233-869f6bf983e3";
    size = "1G";
    backup.groups = [ "offsite" ];
  };
}
