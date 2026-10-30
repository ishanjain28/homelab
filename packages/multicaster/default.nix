{ pkgs, ... }:
let
  src = builtins.fetchGit {
    url = "ssh://git@ssh.git.ishanjain.me:2222/ishan/multicaster.git";
    rev = "0acc1fa43acf4f8ee6d4d032035940ca5a0add63";
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "multicaster";
  version = "0.1.0";
  inherit src;
  cargoHash = "sha256-uYvnpSA5aTXnJvXy/+Lg4vTHccOky1gcLdPpWPJR428=";
}
