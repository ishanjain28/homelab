{ pkgs, ... }:
let
  version = "6.3.0.45";
  openssl11 = pkgs.stdenvNoCC.mkDerivation {
    pname = "openssl-runtime";
    version = "1.1.1w-debian11";

    src = pkgs.fetchurl {
      url = "https://ftp.mpi-inf.mpg.de/pub/linux/mirror/debian-snapshots/bullseye/security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.1_1.1.1w-0+deb11u8_amd64.deb";
      hash = "sha256-3MaKVD3my5VaVwd7ZtzbFfYdHjHgcvLGzECCw32hsA0=";
    };

    nativeBuildInputs = [ pkgs.dpkg ];
    unpackPhase = "dpkg-deb --extract $src .";
    installPhase = ''
      mkdir -p "$out/lib"
      cp usr/lib/x86_64-linux-gnu/libcrypto.so.1.1 "$out/lib/"
      cp usr/lib/x86_64-linux-gnu/libssl.so.1.1 "$out/lib/"
    '';
  };
  mongodb = pkgs.mongodb-ce.overrideAttrs (old: {
    version = "5.0.26";
    src = pkgs.fetchurl {
      url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian11-5.0.26.tgz";
      hash = "sha256-gZai6ZhL1824oQuTAL/f1CDUnsK6jWJQrc/6BHccRgc=";
    };
    buildInputs = old.buildInputs ++ [
      openssl11
      pkgs.xz
    ];
  });
  launcher = pkgs.writeShellScript "omada-controller" ''
    set -euo pipefail

    state_dir="''${OMADA_STATE_DIR:-/var/lib/omada}"

    ${pkgs.coreutils}/bin/install -d -m 0700 \
      "$state_dir/bin" \
      "$state_dir/data" \
      "$state_dir/lib" \
      "$state_dir/logs" \
      "$state_dir/properties" \
      "$state_dir/work"

    ${pkgs.findutils}/bin/find "$state_dir/lib" -mindepth 1 -maxdepth 1 -type l -delete
    for artifact in @out@/lib/*; do
      ${pkgs.coreutils}/bin/ln -s "$artifact" "$state_dir/lib/"
    done
    ${pkgs.coreutils}/bin/ln -sfn ${mongodb}/bin/mongod "$state_dir/bin/mongod"

    for property in @out@/share/omada-controller/properties/*; do
      destination="$state_dir/properties/''${property##*/}"
      if [[ ! -e "$destination" ]]; then
        ${pkgs.coreutils}/bin/install -m 0600 "$property" "$destination"
      fi
    done

    export HOME="$state_dir"
    export XDG_CONFIG_HOME="$state_dir/data/chromium"
    cd "$state_dir/lib"

    exec ${pkgs.jdk17_headless}/bin/java \
      -server \
      -Xms128m \
      -Xmx1536m \
      -XX:MaxHeapFreeRatio=60 \
      -XX:MinHeapFreeRatio=30 \
      -XX:+HeapDumpOnOutOfMemoryError \
      -XX:HeapDumpPath="$state_dir/logs/java_heapdump.hprof" \
      -Deap.home="$state_dir" \
      -Djava.awt.headless=true \
      -cp "$state_dir/lib/*:$state_dir/properties" \
      com.tplink.smb.omada.starter.OmadaLinuxMain
  '';
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "omada-controller";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://static.tp-link.com/upload/software/2026/202609/20260904/Omada_Network_Application_v${version}_linux_x64_20260903171900.tar.gz";
    hash = "sha256-2t9+GH+ishiSo/Jkda4VNg9B1k9XinDwgB0q4Z2p62o=";
  };

  sourceRoot = "Omada_Network_Application_v${version}_linux_x64";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib" "$out/share/omada-controller"
    cp -a lib/. "$out/lib/"
    cp -a properties "$out/share/omada-controller/"
    install -m 0755 ${launcher} "$out/bin/omada-controller"
    substituteInPlace "$out/bin/omada-controller" \
      --replace-fail '@out@' "$out"

    runHook postInstall
  '';

  meta = {
    description = "TP-Link Omada Network Application";
    homepage = "https://support.omadanetworks.com/en/download/software/omada-controller";
    license = pkgs.lib.licenses.unfreeRedistributable;
    mainProgram = "omada-controller";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with pkgs.lib.sourceTypes; [ binaryNativeCode ];
  };
}
