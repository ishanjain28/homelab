{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.secrets;
in
{
  options.${namespace}.secrets.enable = mkEnableOption "SOPS secret management";

  config = mkIf cfg.enable {
    sops = {
      age = {
        sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      };

      gnupg.sshKeyPaths = [ ];
    };
  };
}
