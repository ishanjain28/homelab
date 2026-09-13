{ pkgs, ... }:

pkgs.rustPlatform.buildRustPackage {
  pname = "volume";
  version = "0.1.0";
  src = ../../tools;

  cargoLock.lockFile = ../../tools/Cargo.lock;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/volume \
      --prefix PATH : ${
        pkgs.lib.makeBinPath (
          with pkgs;
          [
            coreutils
            e2fsprogs
            lvm2
            openssh
            systemd
            util-linux
          ]
        )
      }
  '';

  meta = {
    description = "Homelab volume management helper";
    mainProgram = "volume";
    platforms = pkgs.lib.platforms.linux;
  };
}
