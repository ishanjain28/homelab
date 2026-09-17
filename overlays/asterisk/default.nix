_inputs: _final: prev: {
  asterisk = prev.asterisk.overrideAttrs (old: {
    # My fork of asterisk with a patch to make it work on Jio
    version = "22.3.0-jio";
    src = builtins.fetchGit {
      url = "ssh://git@ssh.git.ishanjain.me:2222/ishan/asterisk.git";
      rev = "2b14dbdba06c891036c2fd681037776b1cd3a174";
    };

    preBuild = (old.preBuild or "") + ''
      menuselect/menuselect --disable-category MENUSELECT_CORE_SOUNDS menuselect.makeopts
      menuselect/menuselect --disable-category MENUSELECT_MOH menuselect.makeopts
      menuselect/menuselect --disable-category MENUSELECT_EXTRA_SOUNDS menuselect.makeopts
    '';

    postUnpack = (old.postUnpack or "") + ''
      cp ${
        prev.fetchurl {
          url = "https://downloads.asterisk.org/pub/telephony/sounds/releases/asterisk-core-sounds-en-gsm-1.6.1.tar.gz";
          hash = "sha256-15w9IETUHajzY8RH38zBQL6GtPzEGxylpgqA2lLyTy0=";
        }
      } $sourceRoot/sounds/asterisk-core-sounds-en-gsm-1.6.1.tar.gz
    '';
  });
}
