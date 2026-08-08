{
  lib,
  python3,
  makeWrapper,
  easyeda2kicad,
  fzf,
}: let
  kiutils = python3.pkgs.callPackage ./kiutils.nix {};
in
  python3.pkgs.buildPythonApplication {
    pname = "kicad-parts-manager";
    version = "1.0.0";
    format = "other";

    src = ./.;

    nativeBuildInputs = [makeWrapper];
    propagatedBuildInputs = [python3.pkgs.requests kiutils];

    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      cp kicad-parts.py $out/bin/kicad-parts
      chmod +x $out/bin/kicad-parts
      wrapProgram $out/bin/kicad-parts \
        --prefix PATH : ${lib.makeBinPath [easyeda2kicad fzf]} \
        --run 'export DIGIKEY_CLIENT_ID_FILE="''${DIGIKEY_CLIENT_ID_FILE:-$HOME/.config/sops-nix/secrets/digikey/clientId}"' \
        --run 'export DIGIKEY_CLIENT_SECRET_FILE="''${DIGIKEY_CLIENT_SECRET_FILE:-$HOME/.config/sops-nix/secrets/digikey/clientSecret}"'
    '';

    meta = with lib; {
      description = "KiCad parts manager with LCSC import and Digikey/Mouser metadata";
      license = licenses.mit;
      maintainers = ["heysej"];
      platforms = platforms.unix;
      mainProgram = "kicad-parts";
    };
  }
