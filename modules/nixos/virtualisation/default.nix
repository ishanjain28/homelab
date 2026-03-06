{ lib, namespace, config, ... }:
with lib;
with lib.${namespace};
let cfg = config.${namespace}.virtualisation;
in {
  options.${namespace}.virtualisation = with types; {
    enable = mkEnableOption "Virtualisation support";
  };

  config = mkIf cfg.enable {
    virtualisation = {
      docker = enabled // {
        autoPrune = enabled;
        rootless = enabled // { setSocketVariable = true; };
      };
      oci-containers.backend = "docker";
    };
  };

}
