{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "notify";
  version = "1.0.0";

  src = ./notify;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src $out/bin/notify
    chmod +x $out/bin/notify

    runHook postInstall
  '';

  meta = with lib; {
    description = "Send desktop notifications via kitty OSC 99 escape sequences through tmux";
    license = licenses.mit;
    maintainers = ["heysej"];
    platforms = platforms.unix;
    mainProgram = "notify";
  };
}
