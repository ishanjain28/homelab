{ lib, namespace }: with lib.${namespace};
{
  work = disabled // {
    autoStart = true;
    runtimeId = 31001;
    os = "linux";
    cpus = 12;
    memory = "20000M";
    vlans = [ 10 ];
    disks = [ "/dev/pool/vm-work" ];
    extraArgs = [
      "-smbios"
      "type=1,uuid=f4503765-2f7c-4d0f-8344-ed257ffce88e"
    ];
  };

  win10 = disabled // {
    autoStart = false;
    runtimeId = 31003;
    os = "windows";
    cpus = 12;
    memory = "32G";
    vlans = [ 10 ];
    disks = [ "/dev/pool/vm-win10" ];
    pciDevices = [
      "0000:05:00.0"
      "0000:06:00.0"
    ];
    usbDevices = [
      {
        vendorId = "0461";
        productId = "4002";
      }
      {
        vendorId = "046d";
        productId = "c548";
      }
      {
        vendorId = "1b1c";
        productId = "0c22";
      }
      {
        vendorId = "1d6b";
        productId = "0104";
      }
      {
        vendorId = "1d6b";
        productId = "0104";
      }
    ];
    extraArgs = [
      "-smbios"
      "type=1,uuid=5d7e5765-00f4-48ca-83e6-e154bba7da81"
    ];
  };
}
