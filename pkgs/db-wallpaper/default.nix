{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "db-wallpaper-sync";
  version = "1.0.0";
  pyproject = false;

  src = ./.;

  propagatedBuildInputs = [
    python3Packages.curl-cffi
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp $src/db-wallpaper-sync.py $out/bin/db-wallpaper-sync
    chmod +x $out/bin/db-wallpaper-sync
    runHook postInstall
  '';

  meta = {
    description = "Download wallpapers from Digital Blasphemy at a given resolution";
    license = lib.licenses.mit;
    maintainers = ["heysej"];
    platforms = lib.platforms.linux;
    mainProgram = "db-wallpaper-sync";
  };
}
