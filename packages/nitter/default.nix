{ lib, pkgs, ... }:
let
  rev = "40b264a103a03c0298b51d43a44db3286cad4d5d";

  pcre = pkgs.stdenv.mkDerivation (finalAttrs: {
    pname = "pcre";
    version = "8.45";
    src = pkgs.fetchurl {
      url = "mirror://sourceforge/project/pcre/pcre/${finalAttrs.version}/pcre-${finalAttrs.version}.tar.bz2";
      hash = "sha256-Ta5v3NK7C7bDe1+Xwzwr6VTadDmFNpzdrDVG4yGL/7g=";
    };
    configureFlags = [
      "--enable-utf"
      "--enable-unicode-properties"
    ];
  });

  jester = pkgs.applyPatches {
    src = pkgs.fetchFromGitHub {
      owner = "dom96";
      repo = "jester";
      rev = "2dfac077170c62cd6ffc73e3dcfa29d29c641dcf";
      hash = "sha256-F/zWWGipJ4lBE3njceXn5HBFTYEXB4l2rk6+FfqqZTQ=";
    };
    patches = [ ./jester-ipv6.patch ];
  };
in
pkgs.buildNimPackage (finalAttrs: {
  pname = "nitter";
  version = "0-unstable-2026-11-23";

  src = pkgs.fetchgit {
    url = "https://codeberg.org/shitter/shitter.git";
    inherit rev;
    hash = "sha256-1qK1ibZfmGk/ORC6hck9+ndRL6ThFhVtl1/oFyaj1FI=";
  };

  lockFile = ./lock.json;

  buildInputs = [
    pcre
    pkgs.openssl
  ];

  nimFlags = [
    "--path:${jester}"
    "-d:usePcre"
  ];

  postBuild = ''
    nim compile ${toString finalAttrs.nimFlags} -r tools/gencss
    nim compile ${toString finalAttrs.nimFlags} -r tools/rendermd
  '';

  postInstall = ''
    mkdir -p $out/share/nitter
    cp -r public $out/share/nitter/public
  '';

  meta = {
    homepage = "https://codeberg.org/shitter/shitter";
    license = lib.licenses.agpl3Only;
    mainProgram = "nitter";
  };
})
