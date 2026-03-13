{ lib, ... }:
{
  options.system.migration.volumes = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          uuid = lib.mkOption { type = lib.types.str; };
          containerPath = lib.mkOption { type = lib.types.str; };
          lvPath = lib.mkOption { type = lib.types.str; };
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
