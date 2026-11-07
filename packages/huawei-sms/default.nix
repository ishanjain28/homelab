{ pkgs, ... }:
let
  src = pkgs.fetchFromGitea {
    domain = "git.ishanjain.me";
    owner = "ishan";
    repo = "huawei-sms";
    rev = "8ebd57a1a9cb8fce6a7cc05517f18d58dffdc82e";
    hash = "sha256-yp0lDIuaF3Gze/JrR1TE+Y3PtnC7ZYBZm6QZAMTSma4=";
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
