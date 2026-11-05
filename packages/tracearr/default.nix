{ pkgs, ... }:
let
  pname = "tracearr";
  version = "3.1.3";
  nodejs = pkgs.nodejs-slim_24;
  pnpm = pkgs.pnpm_12.override { nodejs-slim = nodejs; };
  basemapBuild = "20261028";
  basemap = pkgs.stdenvNoCC.mkDerivation {
    name = "tracearr-basemap-${basemapBuild}.pmtiles";
    nativeBuildInputs = [ pkgs.pmtiles ];
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = "sha256-vZkbe7OwCseaRYeqXs5JS1/YjKI+0uVcVZsuK4tFdiQ=";
    buildCommand = "pmtiles extract https://build.protomaps.com/${basemapBuild}.pmtiles $out --maxzoom=8";
  };

  src = pkgs.fetchFromGitHub {
    owner = "connorgallopo";
    repo = "Tracearr";
    rev = "v${version}";
    hash = "sha256-EvnD2wqrI/32GRVQQsWAfaL6ptn/tVezafMxNWKpcUA=";
  };
in
pkgs.stdenv.mkDerivation {
  inherit pname version src;

  TURBO_TELEMETRY_DISABLED = "1";
  pnpm_config_pm_on_fail = "ignore";
  CI = "true";

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-wxtx5Jdx2eSSo+OR6284/4cWbqrlO1kXXknhK06FVaw=";
  };

  nativeBuildInputs = [
    nodejs
    pkgs.makeWrapper
    pkgs.pnpmConfigHook
    pnpm
  ];

  buildPhase = ''
    runHook preBuild

    pnpm turbo run build --env-mode=loose --filter=@tracearr/shared --filter=@tracearr/server --filter=@tracearr/web

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    runtimeRoot="$out/share/${pname}"
    mkdir -p \
      "$out/bin" \
      "$runtimeRoot/apps/server/src/db" \
      "$runtimeRoot/apps/web" \
      "$runtimeRoot/data"

    cp package.json pnpm-lock.yaml pnpm-workspace.yaml "$runtimeRoot/"
    cp apps/server/package.json "$runtimeRoot/apps/server/"
    cp -r apps/server/dist apps/server/scripts "$runtimeRoot/apps/server/"
    cp -r apps/server/src/db/migrations "$runtimeRoot/apps/server/src/db/"
    cp -r apps/web/dist "$runtimeRoot/apps/web/"
    for workspace in packages/shared packages/emails; do
      mkdir -p "$runtimeRoot/$workspace"
      cp "$workspace/package.json" "$runtimeRoot/$workspace/"
      cp -r "$workspace/dist" "$runtimeRoot/$workspace/"
    done
    for workspace in apps/web apps/e2e packages/test-utils packages/translations; do
      mkdir -p "$runtimeRoot/$workspace"
      cp "$workspace/package.json" "$runtimeRoot/$workspace/"
    done
    cp \
      data/GeoLite2-City.mmdb \
      data/GeoLite2-ASN.mmdb \
      data/BASEMAP_NOTICE.txt \
      "$runtimeRoot/data/"
    ln -s ${basemap} "$runtimeRoot/data/basemap.pmtiles"
    ln -s /var/lib/tracearr/image-cache "$runtimeRoot/data/image-cache"

    printf '{"version":"%s","tag":"v%s"}\n' '${version}' '${version}' \
      > "$runtimeRoot/.build-info.json"

    pnpm --dir "$runtimeRoot" install \
      --filter "@tracearr/server..." \
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
