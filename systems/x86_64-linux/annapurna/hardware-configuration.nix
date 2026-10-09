{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  boot.kernelPackages = pkgs.linuxPackages;
  boot.supportedFilesystems.zfs = true;
  boot.zfs.extraPools = [ "main" ];
  boot.zfs.forceImportRoot = false;
  services.zfs.autoScrub = {
    enable = true;
    interval = "*-*-01,16 00:00:00";
  };

  fileSystems."/mnt/wd-4tb" = {
    device = "/dev/disk/by-id/wwn-0x50014ee2bef0ead0-part1";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
