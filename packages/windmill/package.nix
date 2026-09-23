{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  openssl,
  zlib,
  bash,
  bun,
  cargo,
  coreutils,
  deno,
  dotnet-sdk_9,
  flock,
  go,
  nsjail,
  php,
  powershell,
  procps,
  python312,
  uv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "windmill";
  version = "1.817.0";

  src = fetchurl {
    url = "https://github.com/windmill-labs/windmill/releases/download/v${finalAttrs.version}/windmill-amd64";
    hash = "sha256-pD0gLQfAhCJ3+9qP3acGpQ8NFhE5b50xBiltWukYGBM=";
  };

  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    openssl
    zlib
    (lib.getLib stdenv.cc.cc)
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/windmill
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/windmill" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc ]} \
      --prefix PATH : ${
        lib.makeBinPath [
          python312
          procps
          coreutils
        ]
      } \
      --set PYTHON_PATH "${python312}/bin/python3" \
      --set GO_PATH "${go}/bin/go" \
      --set DENO_PATH "${deno}/bin/deno" \
      --set NSJAIL_PATH "${nsjail}/bin/nsjail" \
      --set FLOCK_PATH "${flock}/bin/flock" \
      --set BASH_PATH "${bash}/bin/bash" \
      --set POWERSHELL_PATH "${powershell}/bin/pwsh" \
      --set BUN_PATH "${bun}/bin/bun" \
      --set UV_PATH "${uv}/bin/uv" \
      --set DOTNET_PATH "${dotnet-sdk_9}/bin/dotnet" \
      --set DOTNET_ROOT "${dotnet-sdk_9}/share/dotnet" \
      --set PHP_PATH "${php}/bin/php" \
      --set CARGO_PATH "${cargo}/bin/cargo"
  '';

  meta = {
    changelog = "https://github.com/windmill-labs/windmill/blob/v${finalAttrs.version}/CHANGELOG.md";
    description = "Open-source developer platform to turn scripts into workflows and UIs";
    homepage = "https://windmill.dev";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "windmill";
    platforms = [ "x86_64-linux" ];
  };
})
