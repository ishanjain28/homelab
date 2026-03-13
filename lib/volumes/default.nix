{ lib, ... }:
let
  # Internal helper to generate the base LVM and BindMount structure
  genVolume =
    {
      name,
      size,
      containerPath,
      uuid ? null,
    }:
    {
      # 1. Create the LVM Logical Volume in Disko
      disko.devices.lvm_vg.pool.lvs.${name} = {
        inherit size;
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/var/lib/volumes/${name}";
          # If a UUID is provided, we tell the filesystem to use it.
          # This makes the "identity" of the data machine-independent.
          extraArgs =
            if uuid != null then
              [
                "-U"
                uuid
              ]
            else
              [ ];
        };
      };

      # 2. Map it into the container
      containers.${name}.bindMounts."${containerPath}" = {
        hostPath = "/var/lib/volumes/${name}";
        isReadOnly = false;
      };
    };
in
{
  # Standard Volume: Locked to the machine.
  mkContainerVolume = genVolume;

  mkMigratableContainerVolume =
    {
      name,
      size,
      containerPath,
      uuid,
    }:
    let
      base = genVolume {
        inherit
          name
          size
          containerPath
          uuid
          ;
      };
    in
    lib.recursiveUpdate base {
      system.migration.volumes.${name} = {
        inherit uuid containerPath;
        lvPath = "/dev/pool/${name}";
        isMigratable = true;
      };
    };
}
