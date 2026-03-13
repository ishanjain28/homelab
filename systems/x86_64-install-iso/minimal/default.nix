{
  lib,
  namespace,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # `install-iso` adds wireless support that
  # is incompatible with networkmanager.
  networking.wireless.enable = mkForce false;

  homelab = {
    hardware = {
      networking = enabled;
    };
    services = {
      ssh = enabled;
    };
    system = {
      boot = enabled;
    };
  };

  users.users.ishan = {
    group = "users";
    isNormalUser = true;
  };

  system.stateVersion = "26.05";
}
