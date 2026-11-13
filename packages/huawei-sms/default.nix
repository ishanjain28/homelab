{ pkgs, ... }:
let
  version = "2.1.2";
  src = pkgs.fetchFromGitea {
    domain = "git.ishanjain.me";
    owner = "ishan";
    repo = "huawei-sms";
    tag = "v${version}";
    hash = "sha256-55s+cz8bfiCRX0UM7IXqHOLhxKCTksCExly06goZrwA=";
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "huawei-sms";
  inherit version src;

  cargoHash = "sha256-kuW9mg1eUBMia0jDBy7XEvBNp2v3PoDqFD3ceqEAIXA=";

  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.openssl ];

  RUSTC_BOOTSTRAP = 1;
}
