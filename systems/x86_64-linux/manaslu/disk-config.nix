_: {
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/vda";
      content = {
        type = "gpt";
        partitions = {
          bios = {
            size = "1M";
            type = "EF02";
          };
          root = {
            size = "30G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
          lvm = {
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "pool";
            };
          };
        };
      };
    };
    lvm_vg.pool = {
      type = "lvm_vg";
      lvs.dl = {
        size = "2G";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/home/ishan/dl";
          mountOptions = [ "nofail" ];
        };
      };
    };
  };
}
