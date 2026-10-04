_inputs: _final: prev: {
  authelia = prev.authelia.overrideAttrs (_old: {
    version = "4.39.28";
    src = prev.fetchFromGitHub {
      owner = "authelia";
      repo = "authelia";
      rev = "v4.39.28";
      hash = "sha256-PeXpxj9xD8KYa2W9C1qLmzm1HR7TWseX/33GSRezseM=";
    };
    vendorHash = "sha256-Bi3cAkcVP1ZWFBuy0RfpqW7yqyV5DxSsa6gmtfLgxEA=";
  });
}
