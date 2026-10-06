{
  mkNixConfig = { lib }: {
    generateRegistryFromInputs = true;
    linkInputs = true;
    optimise.automatic = true;

    settings = {
      accept-flake-config = true;
      allowed-users = [ "ishan" ];
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
      keep-derivations = false;
      keep-going = true;
      keep-outputs = false;
      log-lines = 20;
      max-jobs = "auto";
      substitute = true;
      trusted-users = [
        "root"
        "ishan"
      ];
      warn-dirty = false;
    };
  };
}
