_inputs: _final: prev:
let
  version = "1.0.3";
  src = prev.fetchFromGitHub {
    owner = "stalwartlabs";
    repo = "stalwart";
    tag = "v${version}";
    hash = "sha256-4NUb6Peivb5yG4jZSKUSwYijoF4JTvw4+u2uvN4tGqU=";
  };
in
{
  stalwart_1_0 = prev.stalwart_1_0.overrideAttrs (old: {
    inherit src version;
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "stalwart-${version}-vendor";
      hash = "sha256-QOdPdcCa5HxckfMiNkgnkGMuOlRGIfMMylQs7QUGI5Q=";
    };
    cargoBuildFeatures = prev.lib.remove "rocks" old.cargoBuildFeatures;
    cargoCheckFeatures = prev.lib.remove "rocks" old.cargoCheckFeatures;
  });
}
