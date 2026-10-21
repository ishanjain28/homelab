{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.homebrew;
in
{
  options.${namespace}.homebrew.enable = mkBoolOpt true "Whether to manage Homebrew packages declaratively.";

  config = mkIf cfg.enable {
    environment.systemPath = mkBefore [ "/opt/homebrew/bin" ];

    homebrew = enabled // {
      global.brewfile = true;
      onActivation = {
        autoUpdate = false;
        cleanup = "none";
        upgrade = false;
      };
    };
  };
}
