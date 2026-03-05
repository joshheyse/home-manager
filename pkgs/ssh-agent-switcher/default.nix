{
  lib,
  rustPlatform,
  fetchFromGitHub,
}: let
  cargoLock = ./Cargo.lock;
in
  rustPlatform.buildRustPackage {
    pname = "ssh-agent-switcher";
    version = "unstable-2025-10-02";

    src = fetchFromGitHub {
      owner = "jmmv";
      repo = "ssh-agent-switcher";
      rev = "main";
      sha256 = "sha256-p9W0H25pWDB+GCrwLwuVruX9p8b8kICpp+6I11ym1aw=";
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
