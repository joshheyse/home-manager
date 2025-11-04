{
  lib,
  stdenv,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "ssh-fzf";
  version = "1.0.0";

  src = ./ssh-fzf;

  nativeBuildInputs = [makeWrapper];
  buildInputs = [];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src $out/bin/ssh-fzf
    chmod +x $out/bin/ssh-fzf

    runHook postInstall
  '';

  meta = with lib; {
    description = "Interactive SSH host selector using fzf and known_hosts with tmux integration";
    homepage = "https://github.com/heysej/ssh-fzf";
    license = licenses.mit;
    maintainers = ["heysej"];
    platforms = platforms.unix;
    mainProgram = "ssh-fzf";
  };
}
