{ pkgs, ... }:
let
  pname = "seerr";
  version = "0.1.0";
  nodejs = pkgs.nodejs-slim_22;
  pnpm = pkgs.pnpm_10.override { nodejs-slim = nodejs; };

  src = pkgs.fetchFromGitHub {
    owner = "ishanjain28";
    repo = "jellyseerr";
    rev = "762b2dd83d2ba644287e72f2dcea9fbba8d2fc07";
    hash = "sha256-KKR5+z34M5rrybNvWqBBsg+iEx+6EdQeQ1PMa+cIk88=";
  };
in
pkgs.stdenv.mkDerivation {
  inherit pname version src;

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-NiptqZ+r8JsH47sapaKPo3D3DojCn6j0g/OXkhmjNuU=";
  };

  nativeBuildInputs = [
    nodejs
    pkgs.makeWrapper
    pkgs.pnpmConfigHook
    pnpm
  ];

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    pnpm prune --prod --ignore-scripts

    mkdir -p $out/share/${pname} $out/bin
    cp -r package.json dist node_modules $out/share/${pname}/

    # All the extra files it asks for to work properly
    cp -r seerr-api.yml .next $out/share/${pname}/

    cp -r public $out/share/${pname}/

    makeWrapper ${nodejs}/bin/node $out/bin/${pname} \
      --chdir "$out/share/${pname}" \
      --add-flags "$out/share/${pname}/dist/index.js"

    runHook postInstall
  '';

  meta = {
    description = "Jellyseerr";
    homepage = "https://github.com/ishanjain28/jellyseerr";
    mainProgram = pname;
    platforms = pkgs.lib.platforms.linux;
  };
}
