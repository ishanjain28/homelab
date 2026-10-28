{ lib, pkgs, ... }:
pkgs.rustPlatform.buildRustPackage {
  pname = "netflector";
  version = "0.17.1";

  src = pkgs.fetchFromGitHub {
    owner = "netflector";
    repo = "netflector";
    tag = "v0.17.1";
    hash = "sha256-mL8q3nMUmLZa2dBWmR/n4JsAACwMYiM/kaEFhkQR6vA=";
  };
  cargoLock.lockFile = ./Cargo.lock;

  # These DIAL tests need a non-loopback address, absent in the Nix sandbox.
  checkFlags = [
    "--skip=reflector::dial::proxy::tests::a_rest_endpoint_on_this_host_is_not_adopted"
    "--skip=reflector::dial::rewrite::tests::rewrite_location_refuses_a_device_on_this_host"
  ];

  meta = {
    description = "Directional SSDP, WS-Discovery and mDNS reflector";
    homepage = "https://github.com/netflector/netflector";
    license = lib.licenses.bsd2;
    mainProgram = "netflector";
    platforms = lib.platforms.linux;
  };
}
