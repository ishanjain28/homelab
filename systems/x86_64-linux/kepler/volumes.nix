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

  gitea = {
    uuid = "ba59e26e-d0ee-46e7-9d5c-d43cd5850aef";
    size = "10G";
    backup.groups = [
      "hourly"
      "daily"
      "offsite"
    ];
  };

  grafana = {
    uuid = "ad555d93-40a2-40ae-90eb-e3c6c591ef65";
    size = "1G";
    backup.groups = [
      "daily"
      "offsite"
    ];
  };

  loki = {
    uuid = "9f67c61c-3d4c-45d2-b4df-6f1775331d9b";
    size = "20G";
    backup.groups = [
      "daily"
      "offsite"
    ];
  };

  victoriametrics = {
    uuid = "9bc789b1-fa53-4d8e-bd32-760af3d0280a";
    size = "20G";
    backup.groups = [
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
