{ pkgs, ... }:
let
  python = pkgs.python3Packages;

  garth = python.buildPythonPackage rec {
    pname = "garth";
    version = "0.5.21";
    format = "wheel";
    src = pkgs.fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-JLjFF+8k7wMLyhTPTo1616GR2bxg7OYHf+xup0Ol0Dk=";
    };
    dependencies = with python; [
      pydantic
      requests
      requests-oauthlib
    ];
  };

  garminconnect = python.buildPythonPackage rec {
    pname = "garminconnect";
    version = "0.2.28";
    format = "wheel";
    src = pkgs.fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-wyBvHF0lazbQSYeIuWJ180QxKWi1xBXUi2t8e39opc0=";
    };
    dependencies = [ garth ];
  };
in
python.buildPythonApplication {
  pname = "garmin-pg";
  version = "0.1.0";
  pyproject = true;

  src = pkgs.fetchFromGitea {
    domain = "git.ishanjain.me";
    owner = "ishan";
    repo = "garmin";
    rev = "4dee1be71896a6782563f25fdc30964079a8f708";
    hash = "sha256-0BYqmWMxK6b4b2iI1DWj/NAnpk6XVISCPa7T4xMohsE=";
  };

  build-system = [ python.hatchling ];
  dependencies = with python; [
    fitparse
    garminconnect
    psycopg
    python-dotenv
  ];

  dontCheckRuntimeDeps = true;
}
