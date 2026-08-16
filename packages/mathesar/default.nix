{ pkgs, ... }:
let
  version = "0.12.0";

  python = pkgs.python3.override {
    packageOverrides = self: super: {
      clevercsv = super.clevercsv.overridePythonAttrs (_: {
        doCheck = false;
      });

      django-modern-rpc = self.buildPythonPackage rec {
        pname = "django-modern-rpc";
        version = "1.0.3";
        pyproject = true;

        src = pkgs.fetchPypi {
          pname = "django_modern_rpc";
          inherit version;
          hash = "sha256-0GVIsMcEF1B86uUJr8fxEKC8AZphjiy+KZXNgZz3+wU=";
        };

        build-system = [
          self.poetry-core
          self.setuptools
          self.wheel
        ];

        dependencies = [ self.django ];

        doCheck = false;
      };

      django-fernet-encrypted-fields = self.buildPythonPackage rec {
        pname = "django-fernet-encrypted-fields";
        version = "0.1.3";
        pyproject = true;

        src = pkgs.fetchPypi {
          inherit pname version;
          hash = "sha256-jNEAM/C6FT2U8yRVUeW+sbkKFJ2Q5p2YtFgbxl2yO3o=";
        };

        build-system = [
          self.setuptools
          self.wheel
        ];

        dependencies = [
          self.cryptography
          self.django
        ];

        doCheck = false;
      };
    };
  };

  pythonEnv = python.withPackages (
    ps: with ps; [
      adlfs
      azure-identity
      cairosvg
      clevercsv
      django
      django-allauth
      django-fernet-encrypted-fields
      django-modern-rpc
      django-storages
      frozendict
      fsspec
      gunicorn
      pillow
      psycopg
      psycopg2
      pyyaml
      requests
      s3fs
      sqlalchemy
      whitenoise
    ]
  );
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "mathesar";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/mathesar-foundation/mathesar/releases/download/${version}/mathesar.tar.gz";
    hash = "sha256-Sthh6wKinlh/xVsrLqPgMG34pNJ7RL6yRNEEXIkTqTY=";
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  unpackPhase = ''
    runHook preUnpack

    mkdir source
    tar -xzf "$src" -C source
    cd source

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/mathesar" "$out/bin"
    cp -a . "$out/share/mathesar"
    chmod +x "$out/share/mathesar/bin/mathesar"

    cd "$out/share/mathesar"
    env \
      DJANGO_SETTINGS_MODULE=config.settings.production \
      PYTHONPATH="$out/share/mathesar" \
      SECRET_KEY=build-time-static-files \
      "${pythonEnv}/bin/python" -m django collectstatic --noinput --clear

    makeWrapper "$out/share/mathesar/bin/mathesar" "$out/bin/mathesar" \
      --prefix PATH : "${pkgs.lib.makeBinPath [ pythonEnv ]}"

    makeWrapper "${pythonEnv}/bin/python" "$out/bin/mathesar-setup-django" \
      --add-flags "-m mathesar.install" \
      --set DJANGO_SETTINGS_MODULE "config.settings.production" \
      --set PYTHONPATH "$out/share/mathesar" \
      --prefix PATH : "${pkgs.lib.makeBinPath [ pythonEnv ]}"

    runHook postInstall
  '';

  meta.mainProgram = "mathesar";
  passthru = {
    inherit pythonEnv;
  };
}
