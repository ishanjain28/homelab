{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.programs.kitty;
in
{
  options.${namespace}.programs.kitty.enable = mkEnableOption "the kitty terminal";

  config = mkIf cfg.enable {
    programs.kitty = enabled // {
      shellIntegration.mode = "no-rc no-title";
    };
  };
}
