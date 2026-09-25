{
  inputs,
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.services.ssh;
  bool-to-yes-no = value: if value then "yes" else "no";
in
{
  options.${namespace}.services.ssh = {
    enable = mkEnableOption "Setup SSH";
    addRootKeys = mkBoolOpt false "Add the same keys to the root user";
    keys = mkOpt (types.listOf types.nonEmptyStr) (filter (key: key != "") (
      map trim (splitString "\n" (builtins.readFile "${inputs.self}/ssh-keys.txt"))
    )) "List of SSH keys to add";
    package = mkPackageOption pkgs "openssh" { };
    passwordAuth = mkBoolOpt true "Allow password authentication";
    permitRootLogin = mkBoolOpt false "Allow root login";
  };

  config = mkIf cfg.enable {
    services.openssh = enabled // {
      inherit (cfg) package;
      settings = {
        X11Forwarding = mkDefault false;
        PermitRootLogin = mkForce (bool-to-yes-no cfg.permitRootLogin);
        PasswordAuthentication = mkDefault cfg.passwordAuth;
      };
      openFirewall = true;
    };

    users.users.ishan.openssh.authorizedKeys.keys = cfg.keys;
    users.users.root.openssh.authorizedKeys.keys = mkIf cfg.addRootKeys cfg.keys;
  };
}
