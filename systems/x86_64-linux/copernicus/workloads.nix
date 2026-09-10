{ lib, namespace }:
with lib.${namespace};
{
  karakeep = enabled // {
    vlans = [ 50 ];
    runtimeId = 30348;
    volumes = [
      "karakeep"
      "karakeep-meilisearch"
    ];
  };

  omada = enabled // {
    vlans = [ 99 ];
    runtimeId = 30349;
    volumes = [ "omada" ];
  };

  prowlarr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30350;
  };
}
