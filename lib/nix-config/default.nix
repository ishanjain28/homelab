{
  mkNixConfig = { pkgs, lib }: {
    generateNixPathFromInputs = true;
    linkInputs = true;
    distributedBuilds = true;

    extraOptions = ''
      keep-outputs = true
      warn-dirty = false
      keep-derivations = true
    '';

    settings = {
      accept-flake-config = true;
      allowed-users = [ "kepler" ];
      auto-optimise-store = false;
      builders-use-substitutes = true;
      experimental-features = lib.mkForce [
        "auto-allocate-uids"
        "ca-derivations"
        "cgroups"
        "flakes"
        "nix-command"
      ];
      flake-registry = "/etc/nix/registry.json";
      http-connections = 50;
      keep-going = true;
      log-lines = 20;
      max-jobs = "auto";
      sandbox = lib.mkForce (!pkgs.stdenv.isDarwin);
      trusted-users = [ "root" "kepler" ];
      warn-dirty = false;
    };
  };
}
