{
  pkgs,
  measurementUser ? "ripe-atlas",
  measurementGroup ? measurementUser,
}:
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "ripe-atlas-software-probe";
  version = "5130";

  src = pkgs.fetchurl {
    url = "https://github.com/RIPE-NCC/ripe-atlas-software-probe/archive/refs/tags/${finalAttrs.version}.tar.gz";
    hash = "sha256-0rCwPBwnueHPyDKcSGIUHKU9D0b4yzavkqOtwuXSb/Y=";
  };

  nativeBuildInputs = with pkgs; [
    autoreconfHook
    makeWrapper
  ];

  buildInputs = [ pkgs.openssl ];

  hardeningDisable = [ "format" ];

  configureFlags = [
    "--disable-chown"
    "--disable-setcap-install"
    "--disable-systemd"
    "--localstatedir=/var"
    "--runstatedir=/run"
    "--sysconfdir=/var/lib"
    "--with-group=${measurementGroup}"
    "--with-install-mode=probe"
    "--with-measurement-user=${measurementUser}"
    "--with-shell-fixup=${pkgs.bash}/bin/bash"
    "--with-user=${measurementUser}"
  ];

  postPatch = ''
    substituteInPlace bin/arch/generic/generic-ATLAS.sh.in \
      --replace-fail '    chown -R @ripe_atlas_user@:@ripe_atlas_group@ $ATLAS_SYSCONFDIR' '    :'

    substituteInPlace configure.ac \
      --replace-fail 'atlas_spooldir="\''${localstatedir}/spool/ripe-atlas"' 'atlas_spooldir="/var/lib/ripe-atlas/spool"'

    substituteInPlace bin/arch/linux/linux-functions.sh \
      --replace-fail /usr/bin/ssh ${pkgs.openssh}/bin/ssh

    substituteInPlace bin/reginit.sh.in \
      --replace-fail 'cp $KNOWN_HOSTS_REG $ATLAS_STATUS/known_hosts' 'install -m 0600 $KNOWN_HOSTS_REG $ATLAS_STATUS/known_hosts'

    substituteInPlace Makefile.am \
      --replace-fail 'install-exec-local:' 'install-runtime-directories:'
  '';

  installPhase = ''
    runHook preInstall

    installRoot="$TMPDIR/install-root"
    make install DESTDIR="$installRoot"

    mkdir -p "$out"
    cp -a "$installRoot$out/." "$out/"
    install -Dm0644 "$installRoot/var/lib/ripe-atlas/mode" \
      "$out/share/ripe-atlas/defaults/mode"

    wrapProgram "$out/sbin/ripe-atlas" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath (
          with pkgs;
          [
            bash
            coreutils
            gnugrep
            gnused
            iproute2
            openssh
            procps
          ]
        )
      }

    runHook postInstall
  '';

  meta = {
    description = "RIPE Atlas software probe";
    homepage = "https://github.com/RIPE-NCC/ripe-atlas-software-probe";
    license = pkgs.lib.licenses.gpl3Only;
    mainProgram = "ripe-atlas";
    platforms = pkgs.lib.platforms.linux;
  };
})
