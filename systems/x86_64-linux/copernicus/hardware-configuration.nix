{ lib, modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "ahci"
    "virtio_pci"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Copernicus currently runs as a Proxmox VM. Replace this VirtioFS mount with
  # the native disk configuration when the machine moves to bare metal.
  fileSystems = {
    "/mnt/wd-4tb" = {
      device = "wd-4tb";
      fsType = "virtiofs";
    };
    "/main/music" = {
      device = "music";
      fsType = "virtiofs";
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
