# AMD/Xilinx Vivado, runtime-wrapped for NixOS.
#
# Design (see README): the installed tree (~52 GB) lives OUTSIDE the nix store,
# at `installRoot` on /persist, produced once by the `vivado-install` tool
# (passthru.installTool / the `vivado-install` package). This package is just a
# tiny `buildFHSEnv` wrapper that sources that tree's settings and runs vivado
# inside an FHS whose lib set (fhs-libs.nix) satisfies Vivado's dependencies.
#
# Why not copy the tree into the store? At 52 GB the requireFile(tar)->unpack
# route peaks ~104 GB in a 106 GB /nix — too tight. /persist has room and is
# impermanence-persistent, so the wrapper references it directly. The build
# stays cheap and `nix run .#vivado` works; only the install itself is on
# /persist. Rebuild triggers: this recipe / fhs-libs / a nixpkgs bump.
{
  lib,
  pkgs,
  buildFHSEnv,
  writeShellScript,
  callPackage,
  # Root of the out-of-store install (contains <version>/Vivado/...), i.e. the
  # `VIVADO_DEST` the install tool wrote to. Override if you install elsewhere.
  installRoot ? "/persist/xilinx",
}: let
  opts = import ./options.nix;
  fhsLibs = import ./fhs-libs.nix pkgs;
  version = opts.version;

  # Installer lays the tree out as <root>/<version>/Vivado/...
  vivadoRoot = "${installRoot}/${version}/Vivado";
in
  buildFHSEnv {
    name = "vivado";
    # fhsLibs = Vivado's runtime libs (+ coreutils/sed/awk/find already in it);
    # add make/diff so the FHS can also drive HDL Makefile flows (e.g. taxi).
    targetPkgs = _: fhsLibs ++ (with pkgs; [gnumake diffutils]);

    # Source settings64.sh so vivado/vitis/xsct/etc. are on PATH, then run the
    # requested command (default: interactive vivado). The install tree is
    # bind-visible inside the FHS (it lives on /persist, not in the sandbox's
    # replaced /usr,/lib,/bin).
    runScript = writeShellScript "vivado-run" ''
      if [ ! -e "${vivadoRoot}/settings64.sh" ]; then
        echo "vivado: no install at ${vivadoRoot}." >&2
        echo "        run 'nix run .#vivado-install' first (see the package README)." >&2
        exit 1
      fi
      source "${vivadoRoot}/settings64.sh"
      # Vivado's loader resets LD_LIBRARY_PATH and its ldconfig cache misses the
      # ncurses5 compat symlinks, so force the FHS lib dirs onto the search path.
      export LD_LIBRARY_PATH="/usr/lib:/lib''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}"
      if [ "$#" -eq 0 ]; then
        exec vivado
      else
        exec "$@"
      fi
    '';

    passthru = {
      # `nix run .#vivado-install` also reachable as pkgs.vivado.installTool
      installTool = callPackage ./install-tool.nix {};
      inherit installRoot vivadoRoot;
    };

    meta = with lib; {
      description = "AMD/Xilinx Vivado ${version} (FHS wrapper over an out-of-store /persist install)";
      homepage = "https://www.xilinx.com/products/design-tools/vivado.html";
      license = licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "vivado";
    };
  }
