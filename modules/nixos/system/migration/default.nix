{ lib, ... }:
{
  options.system.migration.volumes = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          volumeId = lib.mkOption { type = lib.types.str; };
          uuid = lib.mkOption { type = lib.types.str; };
          host = lib.mkOption { type = lib.types.str; };
          ownerService = lib.mkOption { type = lib.types.str; };
          mountPath = lib.mkOption { type = lib.types.str; };
          size = lib.mkOption { type = lib.types.str; };
          fsType = lib.mkOption { type = lib.types.str; };
          hostPath = lib.mkOption { type = lib.types.str; };
          lvPath = lib.mkOption { type = lib.types.str; };
          owner = {
            user = lib.mkOption { type = lib.types.str; };
            uid = lib.mkOption { type = lib.types.int; };
            group = lib.mkOption { type = lib.types.str; };
            gid = lib.mkOption { type = lib.types.int; };
            mode = lib.mkOption { type = lib.types.str; };
            namespaceBase = lib.mkOption { type = lib.types.int; };
            hostUid = lib.mkOption { type = lib.types.int; };
            hostGid = lib.mkOption { type = lib.types.int; };
          };
          isMigratable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
      }
    );
    default = { };
  };
}
