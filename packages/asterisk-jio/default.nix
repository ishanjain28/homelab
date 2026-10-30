{ namespace, pkgs, ... }:
pkgs.symlinkJoin {
  name = "asterisk-jio-${pkgs.asterisk.version}";
  paths = [
    pkgs.asterisk
    pkgs.${namespace}.res-pjsip-jio
  ];
}
