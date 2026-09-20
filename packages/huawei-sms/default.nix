{ pkgs, ... }:
let
  src = builtins.fetchGit {
    url = "ssh://git@ssh.git.ishanjain.me:2222/ishan/huawei-sms.git";
    rev = "7d3a0d0c54738261e53a18b3eb25cd9a76ff53e8";
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "huawei-sms";
  version = "1.0.0";
  inherit src;

  cargoHash = "sha256-rFmgZPC+4aqCV2Vf7d6pEdflQHvwYyLyaCwBWJHn1Z4=C";

  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.openssl ];

  RUSTC_BOOTSTRAP = 1;
}
