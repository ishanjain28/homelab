{
  mkNixConfig = { lib }: {
    generateNixPathFromInputs = true;
    generateRegistryFromInputs = true;
    linkInputs = true;
    optimise.automatic = true;

    settings = {
      accept-flake-config = true;
      allowed-users = [ "ishan" ];
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
      keep-derivations = true;
      keep-going = true;
      keep-outputs = true;
      log-lines = 20;
      max-jobs = "auto";
      substitute = false;
      trusted-users = [
        "root"
        "ishan"
      ];
      warn-dirty = false;
    };
  };
}
