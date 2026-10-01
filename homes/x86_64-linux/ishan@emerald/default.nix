{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib.${namespace};
{
  ${namespace} = {
    profiles.shell = enabled;
    programs.neovim = enabled;
  };

  home.packages = with pkgs; [
    cachix
    deploy-rs
    nixfmt
    nix-inspect
    nixos-generators
    nixpkgs-review
    nurl
    nvd
    ookla-speedtest
    restic
    ruff
    shfmt
    uv
  ];

  sops = {
    age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
    secrets.gitconfig = {
      sopsFile = lib.snowfall.fs.get-file ".gitconfig";
      format = "binary";
    };
  };

  programs.git.includes = [ { path = config.sops.secrets.gitconfig.path; } ];

  home.stateVersion = "25.11";
}
