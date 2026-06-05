{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage {
  pname = "dwfv";
  version = "0.5";

  src = fetchFromGitHub {
    owner = "psurply";
    repo = "dwfv";
    rev = "v0.5";
    hash = "sha256-MFCuZX7hbfeTxdd31SMOX0xZTU2NuG11wEp/a7g8Gzw=";
  };

  # Upstream ships a Cargo.lock, but buildRustPackage needs it as a Nix path;
  # we vendor a copy here (all deps are from crates.io, no git sources).
  cargoLock.lockFile = ./Cargo.lock;
  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
  '';

  meta = {
    description = "Simple digital (VCD) waveform viewer with vi-like key bindings (terminal TUI)";
    homepage = "https://github.com/psurply/dwfv";
    license = lib.licenses.mit;
    mainProgram = "dwfv";
  };
}
