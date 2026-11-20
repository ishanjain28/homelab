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
  coreutils,
  deno,
  flock,
  gnumake,
  nsjail,
  node-gyp,
  nodejs,
  pkg-config,
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
    # Bun lifecycle scripts expect node-gyp on PATH. Run the Nix-pinned
    # node-gyp implementation with Bun so it selects headers for Bun's
    # advertised Node ABI instead of the Node version used by Nixpkgs.
    makeWrapper "${bun}/bin/bun" "$out/bin/node-gyp" \
      --add-flags "${node-gyp}/lib/node_modules/node-gyp/bin/node-gyp.js"

    # Windmill clears the environment before invoking uv.  Preserve the
    # nix-ld settings in a dedicated launcher so uv-managed, generic Linux
    # Python runtimes can execute while resolving dependencies on NixOS.
    makeWrapper "${uv}/bin/uv" "$out/bin/windmill-uv" \
      --set NIX_LD "${stdenv.cc.bintools.dynamicLinker}" \
      --set NIX_LD_LIBRARY_PATH "${
        lib.makeLibraryPath [
          stdenv.cc.cc
          zlib
          openssl
        ]
      }"

    wrapProgram "$out/bin/windmill" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc ]} \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          nodejs
          python312
          procps
          coreutils
          gnumake
          pkg-config
          stdenv.cc
          stdenv.cc.bintools
        ]
      } \
      --prefix PATH : "$out/bin" \
      --set PYTHON_PATH "${python312}/bin/python3" \
      --set DENO_PATH "${deno}/bin/deno" \
      --set NSJAIL_PATH "${nsjail}/bin/nsjail" \
      --set FLOCK_PATH "${flock}/bin/flock" \
      --set BASH_PATH "${bash}/bin/bash" \
      --set BUN_PATH "${bun}/bin/bun" \
      --set NODE_BIN_PATH "${nodejs}/bin/node" \
      --set UV_PATH "$out/bin/windmill-uv"
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
