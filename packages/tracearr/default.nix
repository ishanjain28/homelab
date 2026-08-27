{ pkgs, ... }:
let
  pname = "tracearr";
  version = "2.1.0";
  nodejs = pkgs.nodejs-slim_24;
  pnpm =
    (pkgs.pnpm_11.override {
      nodejs-slim = nodejs;
    }).overrideAttrs
      (_old: rec {
        version = "11.11.0";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pnpm/-/pnpm-${version}.tgz";
          hash = "sha256-he8u/yFqGukIBMAMjfv6ZoU1NkRlDRCQaok8Ba7c2IQ=";
        };
      });

  src = pkgs.fetchFromGitHub {
    owner = "connorgallopo";
    repo = "Tracearr";
    rev = "v${version}";
    hash = "sha256-075XXIFuOYcshElOD11TAjc2679Y7d8GU1XVuqBMquc=";
  };
in
pkgs.stdenv.mkDerivation {
  inherit pname version src;

  TURBO_TELEMETRY_DISABLED = "1";
  CI = "true";

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-siXWtc8O8lWT+KGxGaPNDeTqXONFZhOHhNdXMwOGS1s=";
  };

  nativeBuildInputs = [
    nodejs
    pkgs.makeWrapper
    pkgs.pnpmConfigHook
    pnpm
  ];

  buildPhase = ''
    runHook preBuild

    pnpm turbo run build --filter=@tracearr/shared --filter=@tracearr/translations --filter=@tracearr/server --filter=@tracearr/web

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      $out/bin \
      $out/share/${pname}/apps/server/src/db \
      $out/share/${pname}/apps/e2e \
      $out/share/${pname}/apps/mobile \
      $out/share/${pname}/apps/web \
      $out/share/${pname}/packages/shared \
      $out/share/${pname}/packages/test-utils \
      $out/share/${pname}/packages/translations

    cp package.json pnpm-lock.yaml pnpm-workspace.yaml $out/share/${pname}/
    cp -r node_modules $out/share/${pname}/

    cp apps/server/package.json $out/share/${pname}/apps/server/
    cp -r apps/server/dist apps/server/scripts $out/share/${pname}/apps/server/
    cp -r apps/server/node_modules $out/share/${pname}/apps/server/
    cp -r apps/server/src/db/migrations $out/share/${pname}/apps/server/src/db/

    cp apps/web/package.json $out/share/${pname}/apps/web/
    cp -r apps/web/dist $out/share/${pname}/apps/web/
    cp -r apps/web/node_modules $out/share/${pname}/apps/web/

    cp apps/e2e/package.json $out/share/${pname}/apps/e2e/
    cp apps/mobile/package.json $out/share/${pname}/apps/mobile/

    cp packages/shared/package.json $out/share/${pname}/packages/shared/
    cp -r packages/shared/dist $out/share/${pname}/packages/shared/
    cp -r packages/shared/node_modules $out/share/${pname}/packages/shared/

    cp packages/test-utils/package.json $out/share/${pname}/packages/test-utils/

    cp packages/translations/package.json $out/share/${pname}/packages/translations/
    cp -r packages/translations/dist $out/share/${pname}/packages/translations/
    cp -r packages/translations/node_modules $out/share/${pname}/packages/translations/

    makeWrapper ${nodejs}/bin/node $out/bin/${pname} \
      --add-flags "$out/share/${pname}/apps/server/dist/index.js"

    runHook postInstall
  '';

  meta = {
    description = "Media server monitoring and activity analytics";
    homepage = "https://github.com/connorgallopo/Tracearr";
    mainProgram = pname;
    platforms = pkgs.lib.platforms.linux;
  };
}
