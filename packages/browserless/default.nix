{ pkgs, ... }:
let
  pname = "browserless";
  version = "1.61.1";
  nodejs = pkgs.nodejs-slim_22;
  buildNpmPackage = pkgs.buildNpmPackage.override { nodejs = pkgs.nodejs_22; };
  hosts = pkgs.writeText "browserless-hosts.json" "[]";
in
buildNpmPackage {
  inherit pname version;

  src = pkgs.fetchurl {
    url = "https://github.com/browserless/browserless/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-ZAHt3mKUd+ZG64puGWer28EibR0SVQ3qfxeVUNkKd+E=";
  };

  npmDepsHash = "sha256-SIZHvvOF/5wil+Se1laGfeOw/C5nAqexUUUTLPXq5Fo=";
  makeCacheWritable = true;
  npmInstallFlags = [ "--omit=optional" ];

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.pkg-config
  ];
  buildInputs = [ pkgs.vips ];

  env = {
    CHROMEDRIVER_SKIP_DOWNLOAD = "true";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PUPPETEER_SKIP_DOWNLOAD = "true";
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = "true";
    SHARP_FORCE_GLOBAL_LIBVIPS = "1";
    npm_config_nodedir = pkgs.nodejs_22;
  };

  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"postinstall": "node ./scripts/postinstall.js",' ""
  '';

  postInstall = ''
    cp ${hosts} "$out/lib/node_modules/browserless-chrome/hosts.json"
    cp package-lock.json "$out/lib/node_modules/browserless-chrome/package-lock.json"

    makeWrapper ${nodejs}/bin/node "$out/bin/browserless" \
      --chdir "$out/lib/node_modules/browserless-chrome" \
      --add-flags "$out/lib/node_modules/browserless-chrome/build/index.js" \
      --set CHROME_BINARY_LOCATION ${pkgs.chromium}/bin/chromium \
      --set CHROMEDRIVER_SKIP_DOWNLOAD true \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --set PUPPETEER_SKIP_DOWNLOAD true \
      --set PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true
  '';

  meta = {
    description = "Headless Chromium as a service";
    homepage = "https://github.com/browserless/browserless";
    license = pkgs.lib.licenses.gpl3Only;
    mainProgram = "browserless";
    platforms = pkgs.lib.platforms.linux;
  };
}
