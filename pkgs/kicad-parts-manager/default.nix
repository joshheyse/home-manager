{
  lib,
  python3,
  makeWrapper,
  easyeda2kicad,
  fzf,
}:
python3.pkgs.buildPythonApplication {
  pname = "kicad-parts-manager";
  version = "1.0.0";
  format = "other";

  src = ./.;

  nativeBuildInputs = [makeWrapper];
  propagatedBuildInputs = [python3.pkgs.requests];

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp kicad-parts.py $out/bin/kicad-parts
    chmod +x $out/bin/kicad-parts
    wrapProgram $out/bin/kicad-parts \
      --prefix PATH : ${lib.makeBinPath [easyeda2kicad fzf]}
  '';

  meta = with lib; {
    description = "KiCad parts manager with LCSC import and Digikey/Mouser metadata";
    license = licenses.mit;
    maintainers = ["heysej"];
    platforms = platforms.unix;
    mainProgram = "kicad-parts";
  };
}
