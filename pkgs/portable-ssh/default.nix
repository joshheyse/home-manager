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

  src = ./.;

  nativeBuildInputs = [makeWrapper];

  dontUnpack = true;
  dontBuild = true;
  # Critical: portable-launcher's shebang must remain `/usr/bin/env bash`
  # so it works on the *remote* host (where /nix/store doesn't exist).
  # nix's stdenv would otherwise rewrite it to /nix/store/.../bash via
  # patchShebangs, which breaks the remote.
  dontPatchShebangs = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src/portable-ssh $out/bin/portable-ssh
    install -Dm755 $src/portable-launcher $out/share/portable-ssh/portable-launcher

    # Wrap so the script's runtime tools come from nix, not from
    # whatever the user's PATH happens to look like. ssh is intentionally
    # NOT in the wrapper PATH — the system openssh has site-tuned config
    # that the nixpkgs build sometimes rejects.
    wrapProgram $out/bin/portable-ssh \
      --prefix PATH : ${lib.makeBinPath [
      rsync
      nix
      coreutils
      gawk
      gnugrep
      gnused
    ]} \
      --set PORTABLE_LAUNCHER_PATH "$out/share/portable-ssh/portable-launcher"

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
