{ pkgs, ... }:
let
  src = builtins.fetchGit {
    url = "ssh://git@ssh.git.ishanjain.me:2222/ishan/pvr-movies-monitor.git";
    rev = "c053464614c1ad0ce8e6b80c95e0cc7aa02cbe77";
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "pvr-movies-monitor";
  version = "0.1.5";
  inherit src;

  cargoHash = "sha256-HCIOtWMOwA7Z2IHuQ13fh1Ux+COkNefrGClADOt7Q18=";
}
