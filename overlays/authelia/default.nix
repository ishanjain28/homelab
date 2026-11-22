_inputs: _final: prev:
let
  version = "4.39.28-unstable-2026-11-18";
  src = prev.fetchFromGitHub {
    owner = "authelia";
    repo = "authelia";
    rev = "22a06dbb355e58477b64e1e322a23ee791df46ce";
    hash = "sha256-FrYp4HVIEroBXU5FTIdLAtJ0WvdUXMxfcYzHVqxrxCk=";
  };
  web = prev.authelia.web.overrideAttrs (old: {
    inherit src version;
    patches = [ ./login-background.patch ];
    postPatch = old.postPatch + ''
      install -m 0444 -t src/assets/images ${../../assets/authelia}/*.webp
    '';
    pnpmDeps = prev.fetchPnpmDeps {
      inherit (old) pname sourceRoot;
      inherit src version;
      pnpm = prev.pnpm_12;
      fetcherVersion = 4;
      hash = "sha256-KIOM75Fq+iEXkwmTOjdsWZi9SD2/kamT4zs4lMLrw4A=";
    };
  });
in
{
  authelia = (prev.authelia.override { authelia-web = web; }).overrideAttrs (old: {
    inherit src version;
    vendorHash = "sha256-jwPct8XxJJOuMYOHpKGaOKzMpGW4y27A7CDhZAxHmeM=";

    # No one who uses my instance needs a language other than English and it's a magnet for bots.
    postPatch = old.postPatch + ''
      find internal/server/locales -mindepth 1 -maxdepth 1 -type d ! -name en -exec rm -r {} +
    '';
  });
}
