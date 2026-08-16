{
  projectRootFile = "flake.nix";

  programs = {
    deadnix.enable = true;
    nixfmt.enable = true;
    shellcheck.enable = true;
    statix.enable = true;
    taplo.enable = true;
    yamlfmt.enable = true;
  };

  settings = {
    formatter = {
      deadnix.includes = [ "*.nix" ];
      nixfmt.includes = [ "*.nix" ];
      statix.includes = [ "*.nix" ];
      shellcheck.excludes = [ "*.envrc" ];
      taplo.excludes = [ "secrets/**" ];
      yamlfmt.excludes = [ "secrets/**" ];
    };
  };
}
