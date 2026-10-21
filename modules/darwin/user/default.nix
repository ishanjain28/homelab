{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.user;
in
{
  options.${namespace}.user.name = mkOpt types.str "ishan" "The primary macOS user.";

  config = {
    system.primaryUser = cfg.name;
    users.users.${cfg.name}.home = "/Users/${cfg.name}";

    programs.fish = enabled // {
      useBabelfish = true;
    };
    environment.shells = [ pkgs.fish ];

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "bkp";
      extraSpecialArgs = { inherit namespace; };
    };
  };
}
