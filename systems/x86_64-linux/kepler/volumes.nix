{
  actual-server = {
    uuid = "7adaa473-69d9-46cd-9328-0ad971095e62";
    size = "512M";
    backup.groups = [
      "hourly"
      "daily"
      "offsite"
    ];
  };

  changedetection = {
    uuid = "3aa2b73b-be43-4239-85e5-933ed3559282";
    mountPath = "/var/lib/changedetection-io";
    size = "1G";
    backup.groups = [
      "daily"
      "offsite"
    ];
  };

  openvscode-server = {
    uuid = "6baec4af-fa52-4153-9e1d-c612777fdf9e";
    size = "10G";
    backup.groups = [
      "daily"
      "offsite"
    ];
  };

  cups = {
    uuid = "e564a94b-273c-4e42-a918-184648476394";
    size = "5G";
    mode = "0755";
    backup.groups = [
      "daily"
      "offsite"
    ];
  };

  ripe-atlas-primary = {
    uuid = "ce89f069-d9bf-49be-b318-f409d1162fae";
    mountPath = "/var/lib/ripe-atlas";
    size = "64M";
    backup.groups = [
      "daily"
      "offsite"
    ];
  };

  ripe-atlas-lte = {
    uuid = "a6a437a0-cb17-46c5-bd8b-c0a5ce983325";
    mountPath = "/var/lib/ripe-atlas";
    size = "64M";
    backup.groups = [
      "daily"
      "offsite"
    ];
  };

}
