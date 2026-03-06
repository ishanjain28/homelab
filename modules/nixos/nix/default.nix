{ lib, pkgs, namespace, ... }:
with lib.${namespace}; {
  documentation = enabled // {
    doc = disabled;
    man = enabled;
    dev = disabled;
  };

  users.users.kepler.packages = with pkgs; [ nix-output-monitor ];

  nix = mkNixConfig { inherit lib pkgs; } // { optimise.automatic = true; };
}
