{ pkgs, ... }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "mikrotik-mib";
  version = "2026-09-14";

  src = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/librenms/librenms/3e19772a0f535d13df6b1f8954d9c4296639443c/mibs/mikrotik/MIKROTIK-MIB";
    hash = "sha256-saZf+ACdK5WBd0QOUwBVeTBSmO783rBi0jazBc4jc/s=";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm444 $src $out/share/snmp/mibs/MIKROTIK-MIB
  '';
}
