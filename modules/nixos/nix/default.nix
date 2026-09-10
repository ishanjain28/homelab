{
  lib,
  pkgs,
  namespace,
  ...
}:
with lib.${namespace};
{
  documentation = enabled // {
    doc = disabled;
    man = disabled;
    dev = disabled;
  };

  programs.nh = enabled // {
    clean = enabled // {
      extraArgs = "--keep 10";
    };
    flake = "$HOME/dotfiles";
  };

  users.users.ishan.packages = with pkgs; [ nix-output-monitor ];

  nix = mkNixConfig { inherit lib pkgs; } // {
    optimise.automatic = true;
  };
}
