{ pkgs, ... }:
let
  pname = "browserless";
  version = "1.61.1";
  nodejs = pkgs.nodejs-slim_22;
  hosts = pkgs.writeText "browserless-hosts.json" "[]";
in
pkgs.buildNpmPackage {
  inherit pname version;
  inherit nodejs;

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
    nodejs.npm
  ];
  buildInputs = [ pkgs.vips ];

  env = {
    CHROMEDRIVER_SKIP_DOWNLOAD = "true";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PUPPETEER_SKIP_DOWNLOAD = "true";
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = "true";
    SHARP_FORCE_GLOBAL_LIBVIPS = "1";
    npm_config_nodedir = nodejs;
  };

  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"postinstall": "node ./scripts/postinstall.js",' ""
  '';

  postInstall = ''
    cp ${hosts} "$out/lib/node_modules/browserless-chrome/hosts.json"
    cp package-lock.json "$out/lib/node_modules/browserless-chrome/package-lock.json"

    sharpBuild="$out/lib/node_modules/browserless-chrome/node_modules/sharp/build"
    cp "$sharpBuild/Release/sharp-linux-x64.node" "$TMPDIR/sharp-linux-x64.node"
    rm -rf "$sharpBuild"
    install -Dm755 "$TMPDIR/sharp-linux-x64.node" "$sharpBuild/Release/sharp-linux-x64.node"
    rm -f "$out/lib/node_modules/browserless-chrome/node_modules/sharp/node-addon-api/nothing.target.mk"

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
