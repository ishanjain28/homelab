{ pkgs, ... }:
let
  src = pkgs.fetchFromGitea {
    domain = "git.ishanjain.me";
    owner = "ishan";
    repo = "pjsip-jio-plugin";
    rev = "3b0a5872416a156decad29eb18b03b58b4708cd9";
    hash = "sha256-H3jA2HGw5eW3wDX2z02+0+0IH6Jik2U3tlaNj6AgojI=";
  };
in
pkgs.asterisk.overrideAttrs (old: {
  pname = "res-pjsip-jio";

  postPatch = old.postPatch + ''
    cp ${src}/res_pjsip_jio.c res/
    cp ${pkgs.asterisk}/include/asterisk/buildopts.h include/asterisk/
  '';

  buildPhase = ''
    runHook preBuild
    make -C res ASTTOPDIR=$PWD SUBDIR=res ASTCFLAGS=-I$PWD/include SOLINK=-shared res_pjsip_jio.so
    runHook postBuild
  '';

  installPhase = ''
    install -Dm555 res/res_pjsip_jio.so -t $out/lib/asterisk/modules
  '';
})
