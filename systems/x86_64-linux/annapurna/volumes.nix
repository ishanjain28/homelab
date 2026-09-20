{
  postgresql-home-primary = {
    uuid = "c89f5053-4f04-42ba-a299-6950e0538235";
    mountPath = "/var/lib/postgresql";
    size = "10G";
    backup.groups = [
      "hourly"
      "daily"
    ];
  };

  postgresql-del-mirror = {
    uuid = "6a5b5582-b8c9-4641-a3ff-e25e9cd06c28";
    mountPath = "/var/lib/postgresql";
    size = "2G";
    backup.groups = [
      "hourly"
      "daily"
    ];
  };

  karakeep = {
    uuid = "e81be5cb-aa35-4c80-96bf-ed55f3c492e9";
    size = "512M";
    backup.groups = [ "daily" ];
  };

  karakeep-meilisearch = {
    uuid = "765a9db8-14cf-4329-80c4-8e7960ca429d";
    ownerService = "karakeep";
    mountPath = "/var/lib/meilisearch";
    size = "256M";
    backup.groups = [ "daily" ];
  };

  omada = {
    uuid = "3aade38f-2d35-4e93-9c68-c303ef36572e";
    mountPath = "/var/lib/omada";
    size = "2G";
    backup.groups = [ "daily" ];
  };

  bazarr = {
    uuid = "c3449bae-8590-44ad-8cc7-58ff813688b4";
    size = "1G";
    backup.groups = [ "daily" ];
  };

  jellyfin = {
    uuid = "95408258-29ea-4970-b0fb-d0e610eef08c";
    size = "90G";
    backup.groups = [ "daily" ];
  };

  qbittorrent = {
    uuid = "d220f35f-449b-4d60-8105-1eac2f0e5bbc";
    size = "256M";
    backup.groups = [ "daily" ];
  };
}
