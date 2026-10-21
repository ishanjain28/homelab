{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.dock;
in
{
  options.${namespace}.dock = {
    enable = mkBoolOpt true "Whether to manage the Dock.";
    apps = mkOpt (types.nullOr (
      types.listOf types.str
    )) null "Full paths of the apps pinned to the Dock, in order. Null leaves them untouched.";
  };

  config = mkIf cfg.enable {
    system.defaults.dock = {
      autohide = true;
      magnification = true;
      largesize = 96;
      tilesize = 40;
      mineffect = "scale";
      orientation = "left";
      show-recents = false;
      persistent-apps = cfg.apps;
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
    };
  };
}
