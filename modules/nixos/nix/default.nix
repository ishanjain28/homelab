{ lib, namespace, ... }: with lib.${namespace};
{
  programs.nh = enabled // {
    clean = enabled // {
      extraArgs = "--keep 10";
    };
  };

  systemd.services.nh-clean.serviceConfig.LogLevelMax = "warning";

  nix = mkNixConfig { inherit lib; };
}
