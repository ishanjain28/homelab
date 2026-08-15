{ pkgs, ... }:
let
  src = pkgs.fetchFromGitea {
    domain = "git.ishanjain.me";
    owner = "ishan";
    repo = "pvr-movies-monitor";
    rev = "c053464614c1ad0ce8e6b80c95e0cc7aa02cbe77";
    hash = "sha256-jUWqLNxr/SQdZ7T+m7YbCW8XmuEp1OOlNWSCbqxU/3k=";
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "pvr-movies-monitor";
  version = "0.1.5";
  inherit src;

  cargoHash = "sha256-HCIOtWMOwA7Z2IHuQ13fh1Ux+COkNefrGClADOt7Q18=";
}
