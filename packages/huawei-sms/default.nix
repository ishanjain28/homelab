{ pkgs, ... }:
let
  src = builtins.fetchGit {
    url = "ssh://git@ssh.git.ishanjain.me:2222/ishan/huawei-sms.git";
    rev = "8ebd57a1a9cb8fce6a7cc05517f18d58dffdc82e";
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "huawei-sms";
  version = "1.0.1";
  inherit src;

  cargoHash = "sha256-/PNdiAS0l/LyJAz53//sFvu/phiTJZk/4OFvcmqTIQ0=";

  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.openssl ];

  RUSTC_BOOTSTRAP = 1;
}
