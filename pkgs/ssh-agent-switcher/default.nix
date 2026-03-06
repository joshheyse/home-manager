{
  lib,
  rustPlatform,
  fetchFromGitHub,
}: let
  cargoLock = ./Cargo.lock;
in
  rustPlatform.buildRustPackage {
    pname = "ssh-agent-switcher";
    version = "1.0.0";

    src = fetchFromGitHub {
      owner = "jmmv";
      repo = "ssh-agent-switcher";
      rev = "ssh-agent-switcher-1.0.0";
      sha256 = "sha256-QsWngp0z7yNOamItmlLJp1K+drdXuAtuIQXcSDkDiQs=";
    };

    cargoLock = {
      lockFile = cargoLock;
    };

    postPatch = ''
      cp ${cargoLock} Cargo.lock
    '';

    meta = {
      description = "Daemon to proxy SSH agent connections to any valid forwarded agent";
      homepage = "https://github.com/jmmv/ssh-agent-switcher";
      license = lib.licenses.bsd3;
      mainProgram = "ssh-agent-switcher";
    };
  }
