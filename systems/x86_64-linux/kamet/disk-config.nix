_: {
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-WD_Blue_SN570_500GB_SSD_23166W400608";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100G";
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
    disk.storage = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_2131CP442213";
      content = {
        type = "gpt";
        partitions.lvm = {
          size = "100%";
          content = {
            type = "lvm_pv";
            vg = "pool";
          };
        };
      };
    };
    lvm_vg.pool = {
      type = "lvm_vg";
      lvs.backups = {
        size = "100G";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/var/lib/backups";
          mountOptions = [ "nofail" ];
        };
      };
    };
  };
}
