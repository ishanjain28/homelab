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
  networking.hostName = mkForce "nixos-bootstrap";

  homelab.profiles.bootstrap = enabled;

  system.stateVersion = "26.05";
}
