_:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      # nvme0n1
      device = "/dev/sda";
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
            size = "60G";
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
      lvs = { }; # Filled dynamically by service calls
    };
  };
}

# {
#   disko.devices = {
#     disk = {
#       main = {
#         type = "disk";
#         # nvme1n1
#         # nvme0n1
#         device = "/dev/sda";
#         content = {
#           type = "gpt";
#           partitions = {
#             boot = {
#               size = "512M";
#               type = "EF00";
#               content = {
#                 type = "filesystem";
#                 format = "vfat";
#                 mountpoint = "/boot";
#                 mountOptions = [ "umask=0077" ];
#               };
#             };
#             root = {
#               size = "100%";
#               content = {
#                 type = "filesystem";
#                 format = "ext4";
#                 mountpoint = "/";
#               };
#             };
#           };
#         };
#       };
#     };
#   };
# }
