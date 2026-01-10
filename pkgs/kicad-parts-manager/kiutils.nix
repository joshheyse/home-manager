{
  lib,
  buildPythonPackage,
  fetchPypi,
}:
buildPythonPackage rec {
  pname = "kiutils";
  version = "1.4.8";
  format = "setuptools";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-GMWAMoPlec/odylV53AlSNcTng/GMNqlee1rK3Z9uEY=";
  };

  # No tests in PyPI distribution
  doCheck = false;

  pythonImportsCheck = ["kiutils"];

  meta = with lib; {
    description = "Simple and SCM-friendly KiCad file parser for KiCad 6.0 and up";
    homepage = "https://github.com/mvnmgrx/kiutils";
    license = licenses.gpl3Plus;
    maintainers = [];
  };
}
