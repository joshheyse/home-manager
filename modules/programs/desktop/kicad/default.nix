{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;

  # KiCad uses different config paths on macOS vs Linux
  kicadConfigDir =
    if isDarwin
    then "${config.home.homeDirectory}/Library/Preferences/kicad/9.0"
    else "${config.home.homeDirectory}/.config/kicad/9.0";

  # Path to config files in this repo
  repoConfigDir = ./config;
in {
  # Sync-back script to copy KiCad settings from machine to repo
  home.packages = [
    (pkgs.writeShellScriptBin "kicad-sync-to-repo" ''
      REPO_DIR="${config.home.homeDirectory}/code/nixos/home-manager/modules/programs/desktop/kicad/config"
      KICAD_DIR="${kicadConfigDir}"

      if [ ! -d "$KICAD_DIR" ]; then
        echo "KiCad config directory not found: $KICAD_DIR"
        exit 1
      fi

      mkdir -p "$REPO_DIR"

      # Sync all json files, hotkeys, and library tables
      for file in "$KICAD_DIR"/*.json "$KICAD_DIR"/*.hotkeys "$KICAD_DIR"/*-table; do
        if [ -f "$file" ]; then
          name=$(basename "$file")
          cp "$file" "$REPO_DIR/$name"
          echo "Synced $name"
        fi
      done

      echo "Done. Don't forget to commit the changes!"
    '')
  ];

  # On activation, copy config files from repo to KiCad config dir
  # Only copies if the destination file doesn't exist (preserves local changes)
  home.activation.kicadConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    KICAD_DIR="${kicadConfigDir}"
    run mkdir -p "$KICAD_DIR"

    # Copy each config file if it doesn't already exist
    for file in ${repoConfigDir}/*; do
      name=$(basename "$file")
      if [ ! -e "$KICAD_DIR/$name" ]; then
        run cp "$file" "$KICAD_DIR/$name"
        run echo "Copied $name to KiCad config"
      fi
    done
  '';
}
