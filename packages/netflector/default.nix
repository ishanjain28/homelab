{ lib, pkgs, ... }:
pkgs.rustPlatform.buildRustPackage {
  pname = "netflector";
  version = "0.17.1-ssdp";

  src = pkgs.fetchgit {
    url = "https://git.ishanjain.me/ishan/netflector.git";
    rev = "f06bdf3b6c77230922d2c15198bb09b5729d1585";
    hash = "sha256-Z8scLWiP/Mk/LOMyXNC8keWBZ2hEgMt/2FQBoQc/FtY=";
  };
  cargoLock.lockFile = ./Cargo.lock;

  # These DIAL tests need a non-loopback address, absent in the Nix sandbox.
  checkFlags = [
    "--skip=reflector::dial::proxy::tests::a_rest_endpoint_on_this_host_is_not_adopted"
    "--skip=reflector::dial::rewrite::tests::rewrite_location_refuses_a_device_on_this_host"
  ];

  meta = {
    description = "Directional SSDP, WS-Discovery and mDNS reflector";
    homepage = "https://git.ishanjain.me/ishan/netflector";
    license = lib.licenses.bsd2;
    mainProgram = "netflector";
    platforms = lib.platforms.linux;
  };
}
