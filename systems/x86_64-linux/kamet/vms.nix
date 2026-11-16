{ lib, namespace }: with lib.${namespace};
{
  win11 = enabled // {
    autoStart = true;
    runtimeId = 31002;
    os = "windows";
    cpus = 10;
    threads = 2;
    cpuPins = [
      1
      7
      2
      8
      3
      9
      4
      10
      5
      11
    ];
    cpuAffinity = "0,6";
    memory = "10G";
    vlans = [ 10 ];
    disks = [ "/dev/pool/vm-win11" ];
    virtioScsiController = true;
    usbDevices = [
      {
        vendorId = "04b8";
        productId = "08aa";
      }
    ];
    extraArgs = [
      "-smbios"
      "type=1,uuid=3f962a7c-c321-4c99-8516-83ed0c273b92"
    ];
  };
}
