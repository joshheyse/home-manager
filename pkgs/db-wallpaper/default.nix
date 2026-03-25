{
  lib,
  writeShellApplication,
  curl,
  jq,
  coreutils,
  file,
  gnused,
  gnugrep,
}:
writeShellApplication {
  name = "db-wallpaper-sync";
  runtimeInputs = [curl jq coreutils file gnused gnugrep];
  text = builtins.readFile ./db-wallpaper-sync.sh;

  meta = {
    description = "Download wallpapers from Digital Blasphemy at a given resolution";
    license = lib.licenses.mit;
    maintainers = ["heysej"];
    platforms = lib.platforms.unix;
    mainProgram = "db-wallpaper-sync";
  };
}
