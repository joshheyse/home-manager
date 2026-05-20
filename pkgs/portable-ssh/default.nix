{
  lib,
  stdenv,
  makeWrapper,
  rsync,
  openssh,
  nix,
  coreutils,
  gawk,
  gnugrep,
  gnused,
}:
stdenv.mkDerivation {
  pname = "portable-ssh";
  version = "0.1.0";

  src = ./portable-ssh;

  nativeBuildInputs = [makeWrapper];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/portable-ssh

    # Wrap so the script's runtime tools come from nix, not from
    # whatever the user's PATH happens to look like. ssh and kitten
    # are intentionally NOT in the wrapper PATH — kitten lives in the
    # user's kitty profile, and we want the system ssh by default.
    wrapProgram $out/bin/portable-ssh \
      --prefix PATH : ${lib.makeBinPath [
      rsync
      openssh
      nix
      coreutils
      gawk
      gnugrep
      gnused
    ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "ssh wrapper that bootstraps a nix-portable home-manager environment on the remote host";
    license = licenses.mit;
    maintainers = ["heysej"];
    platforms = platforms.linux;
    mainProgram = "portable-ssh";
  };
}
