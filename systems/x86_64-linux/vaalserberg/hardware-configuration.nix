{ modulesPath, lib, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "sd_mod"
  ];
  swapDevices = [
    {
      device = "/swapfile";
      size = 2048;
    }
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
