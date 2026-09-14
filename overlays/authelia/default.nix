_inputs: _final: prev: {
  authelia = prev.authelia.overrideAttrs (_old: {
    version = "4.39.26";
    src = prev.fetchFromGitHub {
      owner = "authelia";
      repo = "authelia";
      rev = "v4.39.26";
      hash = "sha256-CFgv7H8no8Z4gYXheEKPyi8C7FGRC77kNqGnIjra3bA=";
    };
    vendorHash = "sha256-Bi3cAkcVP1ZWFBuy0RfpqW7yqyV5DxSsa6gmtfLgxEA=";
  });
}
