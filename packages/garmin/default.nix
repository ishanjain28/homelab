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
    rev = "dfac170bce0936f94ff09cbbe5f14b31c0ebaaf8";
    hash = "sha256-Y4JecNL0yG0tZK5q7R7km1/U2UtSdJpWe2hJmGAbwYI=";
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
