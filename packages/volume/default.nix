{ pkgs, ... }:

pkgs.rustPlatform.buildRustPackage {
  pname = "volume";
  version = "0.1.0";
  src = ../../tools;

  cargoLock.lockFile = ../../tools/Cargo.lock;

  meta = {
    description = "Homelab volume management helper";
    mainProgram = "volume";
    platforms = pkgs.lib.platforms.linux;
  };
}
