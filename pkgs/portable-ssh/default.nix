{
  lib,
  stdenv,
  makeWrapper,
  rsync,
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

    # Pin the script's text-processing tools to nix copies so behavior
    # doesn't depend on the user's PATH. Notably, ssh is NOT pinned —
    # we want to use whatever ssh the user has configured, with their
    # site-specific config and host aliases. Pinning a different
    # openssh build here causes silent auth/parse failures on hosts
    # whose ~/.ssh/config the nix-shipped openssh rejects.
    wrapProgram $out/bin/portable-ssh \
      --prefix PATH : ${lib.makeBinPath [
      rsync
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
