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
  options.${namespace}.secrets = with types; {
    enable = mkEnableOption "SOPS secret management";

    sshKeyPaths = mkOpt (listOf path) [
      "/etc/ssh/ssh_host_ed25519_key"
    ] "SSH private keys imported as age identities for decrypting secrets.";
  };

  config = mkIf cfg.enable {
    sops = {
      age = {
        inherit (cfg) sshKeyPaths;
      };
    };
  };
}
