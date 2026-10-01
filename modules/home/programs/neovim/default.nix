{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.programs.neovim;
in
{
  options.${namespace}.programs.neovim.enable = mkEnableOption "neovim as the default editor";

  config = mkIf cfg.enable {
    programs.neovim = enabled // {
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      withPython3 = false;
      withRuby = false;
    };
  };
}
