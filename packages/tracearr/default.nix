{ pkgs, ... }:
let
  pname = "tracearr";
  version = "2.2.3";
  nodejs = pkgs.nodejs-slim_24;
  pnpm = (pkgs.pnpm_11.override { nodejs-slim = nodejs; }).overrideAttrs (_old: rec {
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
    hash = "sha256-IJYfpQqb3HwvacjK0+TBLd+so5BOPertjuy+EwxV+iI=";
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
    hash = "sha256-Xt2pDiNSkq/WUG+HBj/u9Y40jRRArJhkL5VpEoan3D4=";
  };

  nativeBuildInputs = [
    nodejs
    pkgs.makeWrapper
    pkgs.pnpmConfigHook
    pnpm
  ];

  buildPhase = ''
    runHook preBuild

    pnpm turbo run build --filter=@tracearr/shared --filter=@tracearr/server --filter=@tracearr/web

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    runtimeRoot="$out/share/${pname}"
    mkdir -p \
      "$out/bin" \
      "$runtimeRoot/apps/server/src/db" \
      "$runtimeRoot/apps/web" \
      "$runtimeRoot/data" \
      "$runtimeRoot/packages/shared"

    cp package.json pnpm-lock.yaml pnpm-workspace.yaml "$runtimeRoot/"
    cp apps/server/package.json "$runtimeRoot/apps/server/"
    cp -r apps/server/dist apps/server/scripts "$runtimeRoot/apps/server/"
    cp -r apps/server/src/db/migrations "$runtimeRoot/apps/server/src/db/"
    cp -r apps/web/dist "$runtimeRoot/apps/web/"
    cp packages/shared/package.json "$runtimeRoot/packages/shared/"
    cp -r packages/shared/dist "$runtimeRoot/packages/shared/"
    cp \
      data/GeoLite2-City.mmdb \
      data/GeoLite2-ASN.mmdb \
      data/basemap.pmtiles \
      data/BASEMAP_NOTICE.txt \
      "$runtimeRoot/data/"
    ln -s /var/lib/tracearr/image-cache "$runtimeRoot/data/image-cache"

    printf '{"version":"%s","tag":"v%s"}\n' '${version}' '${version}' \
      > "$runtimeRoot/.build-info.json"

    pnpm --dir "$runtimeRoot" install \
      --prod \
      --offline \
      --frozen-lockfile \
      --ignore-scripts

    makeWrapper ${nodejs}/bin/node $out/bin/${pname} \
      --chdir "$runtimeRoot" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.postgresql ]} \
      --set APP_VERSION '${version}' \
      --set APP_TAG 'v${version}' \
      --add-flags "$runtimeRoot/apps/server/dist/index.js"

    runHook postInstall
  '';

  meta = {
    description = "Media server monitoring and activity analytics";
    homepage = "https://github.com/connorgallopo/Tracearr";
    mainProgram = pname;
    platforms = pkgs.lib.platforms.linux;
  };
}
