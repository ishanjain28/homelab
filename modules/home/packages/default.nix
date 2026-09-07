{
  lib,
  namespace,
  pkgs,
  ...
}:
{
  home.shellAliases = lib.${namespace}.shellAliases;

  home.packages = with pkgs; [
    cachix
    curl
    deploy-rs
    difftastic
    diskus
    fd
    git
    just
    jq
    nixfmt
    nix-inspect
    nixos-generators
    nixpkgs-review
    nurl
    nvd
    ookla-speedtest
    ripgrep
    restic
    ruff
    scc
    shfmt
    unzip
    uv
    whois
    yq
    zip
  ];
}
