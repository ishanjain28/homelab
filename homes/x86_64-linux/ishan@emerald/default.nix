{ lib, namespace, ... }: with lib.${namespace};
{
  profiles.${namespace} = {
    neovim = disabled;
    oh-my-posh = enabled;
  };

  shells.${namespace}.bash = enabled;

  home.stateVersion = "25.11";
}
