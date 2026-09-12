{
  mkNixConfig = { pkgs, lib }: {
    generateNixPathFromInputs = true;
    linkInputs = true;
    distributedBuilds = false;

    extraOptions = ''
      keep-outputs = true
      warn-dirty = false
      keep-derivations = true
    '';

    settings = {
      accept-flake-config = true;
      allowed-users = [ "ishan" ];
      auto-optimise-store = true;
      builders-use-substitutes = false;
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
      sandbox = lib.mkForce (!pkgs.stdenv.hostPlatform.isDarwin);
      substitute = false;
      trusted-users = [
        "root"
        "ishan"
      ];
      warn-dirty = false;
    };
  };
}
