{ pkgs, ... }:
let
  src = pkgs.fetchFromGitea {
    domain = "git.ishanjain.me";
    owner = "ishan";
    repo = "multicaster";
    rev = "0acc1fa43acf4f8ee6d4d032035940ca5a0add63";
    hash = "sha256-V4n7q3n2Z65D2l4KWyA8nMwJBRAH4JtZWk+98W8tGAY=";
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "multicaster";
  version = "0.1.0";
  inherit src;
  cargoHash = "sha256-uYvnpSA5aTXnJvXy/+Lg4vTHccOky1gcLdPpWPJR428=";
}
