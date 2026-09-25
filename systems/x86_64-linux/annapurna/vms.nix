{ lib, namespace }: with lib.${namespace};
{
  win11 = disabled // {
    autoStart = false;
    runtimeId = 31002;
    os = "windows";
    cpus = 12;
    memory = "16G";
    vlans = [ 10 ];
    disks = [ "/dev/pool/vm-win11" ];
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
