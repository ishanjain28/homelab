{ pkgs, ... }:
let
  src = builtins.fetchGit {
    url = "ssh://git@ssh.git.ishanjain.me:2222/ishan/pjsip-jio-plugin.git";
    rev = "3b0a5872416a156decad29eb18b03b58b4708cd9";
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
