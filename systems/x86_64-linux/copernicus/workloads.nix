{ lib, namespace }: with lib.${namespace};
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

  radarr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30354;
    shares = [ "wd-4tb" ];
  };

  sonarr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30355;
    shares = [ "wd-4tb" ];
  };

  bazarr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30356;
    volumes = [ "bazarr" ];
    shares = [ "wd-4tb" ];
  };

  lidarr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30358;
    shares = [ "music" ];
  };

  unpackerr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30359;
    shares = [ "wd-4tb" ];
  };

  jellyfin = enabled // {
    vlans = [ 50 ];
    runtimeId = 30360;
    volumes = [ "jellyfin" ];
    shares = [
      "wd-4tb"
      "music"
    ];
    devices = [ "render" ];
  };

  nitter = enabled // {
    vlans = [ 50 ];
    runtimeId = 30351;
  };

  caddy = enabled // {
    vlans = [
      50
      140
    ];
    runtimeId = 30352;
    configFile = "secrets/caddy/home.json";
  };
}
