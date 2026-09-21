{ lib, namespace }: with lib.${namespace};
{
  work = disabled // {
    autoStart = false;
    runtimeId = 31001;
    os = "linux";
    cpus = 8;
    memory = "16G";
    vlans = [ 10 ];
    vnc = 0;
    disks = [ { device = "/dev/disk/by-id/nvme-CHANGEME-work"; } ];
    pciDevices = [
      "0000:01:00.0"
      "0000:01:00.1"
    ];
    usbDevices = [
      {
        vendorId = "046d";
        productId = "c52b";
      }
    ];
  };

  win11 = disabled // {
    autoStart = false;
    runtimeId = 31002;
    os = "windows";
    cpus = 8;
    memory = "16G";
    vlans = [ 10 ];
    vnc = 1;
    secureBoot = true;
    tpm = true;
    disks = [ ];
    pciDevices = [
      "0000:02:00.0"
      "0000:02:00.1"
      "0000:03:00.0"
    ];
    usbDevices = [ ];
  };

  win10 = disabled // {
    autoStart = false;
    runtimeId = 31003;
    os = "windows";
    cpus = 4;
    memory = "8G";
    vlans = [ 10 ];
    vnc = 2;
    disks = [ { device = "/dev/pool/vm-win10"; } ];
    pciDevices = [ ];
    usbDevices = [ ];
  };
}
