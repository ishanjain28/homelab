{ pkgs, ... }:
let
  pname = "airtrail";
  version = "3.14.0";
  nodejs = pkgs.nodejs-slim_22;

  src = pkgs.fetchFromGitHub {
    owner = "johanohly";
    repo = "AirTrail";
    rev = "v${version}";
    hash = "sha256-6JOK3g4ADGZ1rLu2BZ4nPDboqNCYaOpSmF/a9N3lasY=";
  };

  nodeModules =
    {
      suffix,
      flags,
      hash,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      name = "${pname}-node-modules-${suffix}-${version}";
      inherit src;
      nativeBuildInputs = [ pkgs.bun ];
      dontConfigure = true;
      dontFixup = true;
      buildPhase = ''
        runHook preBuild
        export HOME=$TMPDIR
        bun install --frozen-lockfile --ignore-scripts --no-progress ${flags}
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        rm -rf node_modules/.cache
        cp -r node_modules $out
        runHook postInstall
      '';
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = hash;
    };

  buildModules = nodeModules {
    suffix = "build";
    flags = "";
    hash = "sha256-H4VtzOGyOIQ3gsYF7GfN6U3vFWSCe7S69T4z6nYaDF8=";
  };

  prodModules = nodeModules {
    suffix = "prod";
    flags = "--production";
    hash = "sha256-TWDgsz/Yba8uNPC7rXtsZ9Vn+Lghd0yD7xiVvGYiFxE=";
  };
in
pkgs.stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    nodejs
    pkgs.bun
    pkgs.makeWrapper
  ];

  configurePhase = ''
    runHook preConfigure
    cp -r ${buildModules} node_modules
    chmod -R u+w node_modules
    patchShebangs node_modules
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    NODE_ENV=production bun run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    runtimeRoot="$out/share/${pname}"
    mkdir -p "$out/bin" "$runtimeRoot/prisma" "$runtimeRoot/docker"
    cp -r build package.json "$runtimeRoot/"
    cp -r prisma/migrations "$runtimeRoot/prisma/"
    cp docker/migrate.js docker/admin.js "$runtimeRoot/docker/"
    cp -r ${prodModules} "$runtimeRoot/node_modules"

    makeWrapper ${nodejs}/bin/node $out/bin/${pname} \
      --chdir "$runtimeRoot" \
      --add-flags "$runtimeRoot/build"
    makeWrapper ${nodejs}/bin/node $out/bin/${pname}-migrate \
      --chdir "$runtimeRoot" \
      --add-flags "$runtimeRoot/docker/migrate.js"
    makeWrapper ${nodejs}/bin/node $out/bin/${pname}-admin \
      --chdir "$runtimeRoot" \
      --add-flags "$runtimeRoot/docker/admin.js"

    runHook postInstall
  '';

  meta = {
    description = "Personal flight tracking system";
    homepage = "https://github.com/johanohly/AirTrail";
    mainProgram = pname;
    platforms = pkgs.lib.platforms.linux;
  };
}
