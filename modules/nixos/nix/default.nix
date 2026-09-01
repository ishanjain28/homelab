{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib.${namespace};
{
  documentation = enabled // {
    doc = disabled;
    man = enabled;
    dev = disabled;
  };

  programs.nh = enabled // {
    clean.enable = config.${namespace}.profiles.server.enable;
    flake = "$HOME/dotfiles";
  };

  users.users.ishan.packages = with pkgs; [ nix-output-monitor ];

  nix = mkNixConfig { inherit lib pkgs; } // {
    optimise.automatic = true;
  };
}
