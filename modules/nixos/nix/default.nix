{ lib, namespace, ... }: with lib.${namespace};
{
  programs.nh = enabled // {
    clean = enabled // {
      extraArgs = "--keep 10";
    };
  };

  nix = mkNixConfig { inherit lib; };
}
