{ lib, namespace }: with lib.${namespace};
{
  work = enabled // {
    autoStart = true;
    runtimeId = 31001;
    os = "linux";
    cpus = 12;
    memory = "20000M";
    cpuAffinity = "1-5,13-17";
    vlans = [ 10 ];
    disks = [ "/dev/pool/work-linux" ];
    extraArgs = [
      "-smbios"
      "type=1,uuid=f4503765-2f7c-4d0f-8344-ed257ffce88e"
    ];
  };

  win10 = enabled // {
    autoStart = false;
    runtimeId = 31003;
    os = "windows";
    cpus = 12;
    threads = 2;
    cpuPins = [
      6
      18
      7
      19
      8
      20
      9
      21
      10
      22
      11
      23
    ];
    cpuAffinity = "0,12";
    memory = "32G";
    hugepages = true;
    vlans = [ 10 ];
    disks = [ "/dev/pool/gaming-1" ];
    pciDevices = [
      "0000:0c:00.0"
      "0000:0c:00.1"
      "0000:04:00.0"
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
    ];
    extraArgs = [
      "-smbios"
      "type=1,uuid=5d7e5765-00f4-48ca-83e6-e154bba7da81"
    ];
  };
}
