{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.jellyfin;
  renderDevice = "/dev/dri/renderD128";
in
{
  options.${namespace}.services.jellyfin = mkServiceOptions {
    name = "jellyfin";
    description = "Jellyfin media server";
    endpoints = {
      web.port = 8080;
    };
    monitor = enabled // {
      endpoint = "web";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    resources = {
      CPUQuota = "1200%";
      MemoryMax = "8G";
      TasksMax = 2048;
    };

    containerConfig = {
      environment.etc.jellyfin.source = "/var/lib/jellyfin/config";

      services.jellyfin = enabled // {
        openFirewall = false;
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
        hardwareAcceleration = {
          enable = true;
          type = "qsv";
          device = renderDevice;
        };
        cacheDir = "/var/lib/jellyfin/cache";
        forceEncodingConfig = true;
        transcoding = {
          enableHardwareEncoding = true;
          enableToneMapping = true;
          hardwareDecodingCodecs = {
            h264 = true;
            hevc = true;
            hevc10bit = true;
            mpeg2 = true;
            vc1 = true;
            vp8 = true;
            vp9 = true;
          };
          hardwareEncodingCodecs.hevc = true;
        };
      };

      hardware.graphics = enabled // {
        extraPackages = with pkgs; [
          intel-media-driver
          intel-vaapi-driver
          intel-compute-runtime
          vpl-gpu-rt
        ];
      };

      systemd.services.jellyfin.serviceConfig = {
        PrivateUsers = mkForce false;
        UMask = mkForce "0007";
      };
    };
  });
}
