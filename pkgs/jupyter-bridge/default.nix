{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "jupyter-bridge";
  version = "1.0.0";

  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/jupyter-bridge
    cp $src/cell-bridge.py $out/lib/jupyter-bridge/cell-bridge.py
    cp $src/jupyter-bridge $out/bin/jupyter-bridge
    chmod +x $out/bin/jupyter-bridge

    substituteInPlace $out/bin/jupyter-bridge \
      --replace-warn '@CELL_BRIDGE_PY@' "$out/lib/jupyter-bridge/cell-bridge.py"

    runHook postInstall
  '';

  meta = with lib; {
    description = "CLI and daemon for executing code on a Jupyter kernel via named pipe";
    license = licenses.mit;
    maintainers = ["heysej"];
    platforms = platforms.unix;
    mainProgram = "jupyter-bridge";
  };
}
