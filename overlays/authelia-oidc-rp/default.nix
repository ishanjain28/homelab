_inputs: _final: prev:
let
  version = "4.39.28-unstable-2026-11-15";
  src = prev.fetchFromGitHub {
    owner = "authelia";
    repo = "authelia";
    rev = "f3414f7c102d537750ba076dff8e17f5ff00aaa8";
    hash = "sha256-liwckqFN5ed+ezZajewvG9MlxzkpSXJ5bep+FkSZ7j4=";
  };
  web = prev.authelia.web.overrideAttrs (old: {
    inherit src version;
    pnpmDeps = prev.fetchPnpmDeps {
      inherit (old) pname sourceRoot;
      inherit src version;
      pnpm = prev.pnpm_12;
      fetcherVersion = 4;
      hash = "sha256-TqY6sFAXvte1WMQ2HWLPfH4A2e3bLgxMFYydPhSU6z8=";
    };
  });
in
{
  authelia = (prev.authelia.override { authelia-web = web; }).overrideAttrs {
    inherit src version;
    vendorHash = "sha256-qWEsDOoD/iiP2Z4eh0wOb7w096rdstm+mFCwY3auogM=";
  };
}
