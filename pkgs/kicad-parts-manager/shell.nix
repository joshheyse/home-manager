{pkgs ? import <nixpkgs> {}}:
let
  kiutils = pkgs.python3.pkgs.buildPythonPackage rec {
    pname = "kiutils";
    version = "1.4.8";
    format = "setuptools";

    src = pkgs.python3.pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-GMWAMoPlec/odylV53AlSNcTng/GMNqlee1rK3Z9uEY=";
    };

    doCheck = false;
    pythonImportsCheck = ["kiutils"];
  };

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.requests
    kiutils
  ]);
in
pkgs.mkShell {
  buildInputs = [
    pythonEnv
    pkgs.easyeda2kicad
    pkgs.fzf
  ];

  shellHook = ''
    echo "kicad-parts-manager dev shell"
    echo "Run: python3 kicad-parts.py import C2040"
  '';
}
