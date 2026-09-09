{
  karakeep = {
    uuid = "e81be5cb-aa35-4c80-96bf-ed55f3c492e9";
    size = "512M";
  };

  karakeep-meilisearch = {
    uuid = "765a9db8-14cf-4329-80c4-8e7960ca429d";
    ownerService = "karakeep";
    mountPath = "/var/lib/meilisearch";
    size = "256M";
  };

  omada = {
    uuid = "3aade38f-2d35-4e93-9c68-c303ef36572e";
    mountPath = "/var/lib/omada";
    size = "2G";
  };
}
