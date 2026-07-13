# Vivado (Nix)

Packages AMD/Xilinx Vivado for NixOS, in the spirit of `sfc-nix`/OpenOnload:
proprietary, login-walled, supplied out-of-band. Vivado isn't in nixpkgs
(unfree, ~tens of GB, license-walled), so we build it locally.

Motivating use case: building the taxi `fpga_X3522` bitstream for the Alveo
X3522 (`xcux35-vsva1365-3-e`) — verified end-to-end (synth → P&R →
`write_bitstream`, 17.7 MB `.bit`, 0 errors).

**Edition matters (but no paid license does).** `xcux35` is a Virtex
UltraScale+ part. The free **Standard** edition installs it as a *non-timing*
device: synthesis works, but implementation dies with "Cannot run timing on a
non-timing device". The **Enterprise** edition ships the timing/speed data
(58G family data 338 MB → 1015 MB) and the full build succeeds on the built-in
entitlement — **no Enterprise `.lic` required**. Hence the tool defaults to
`edition = "Vivado ML Enterprise"`. (Small/7-series parts — Artix-7,
Zynq-7000 — work fine under Standard.)

## Design: keep the installer out of the store

The AMD unified installer is ~103 GB; the device-limited install is ~tens of
GB. Both cannot coexist on the 106 GB `/nix` partition, so we do **not** feed
the installer to Nix. Instead:

1. **`vivado-install`** (this package's tool) does a one-time, device-limited
   install onto `/persist`, *outside* Nix, driven by the host's **nix-ld**.
2. That installed tree is tarred and `requireFile`d by **`default.nix`**, which
   FHS-wraps it. Only the necessary bits enter `/nix`.

**Rebuild triggers:** the installed-tree hash (a new version/module set), this
recipe, or a nixpkgs bump — *not* the original installer's sha (Nix never sees
it). Re-running the install is a manual step, only when upgrading Vivado.

Requires `programs.nix-ld.enable = true` on the host (already set on desktop).

## Install options live in Nix

`options.nix` holds the installer's product/edition/module catalog as Nix data
(captured from `xsetup -b ConfigGen`, 2025.2). The tool is parameterised:

```nix
# defaults: Vivado ML Standard + the Virtex UltraScale+ 58G family (xcux35)
pkgs.vivado-install

# override the device modules or edition
pkgs.vivado-install.override {
  edition = "Vivado ML Enterprise";
  enabledModules = [ "Virtex UltraScale+ 58G FPGAs" "Kintex-7 FPGAs" ];
}
```

Unknown module names fail at eval (checked against `options.nix` `allModules`).
`xcux35` was verified to live in **Virtex UltraScale+ 58G FPGAs** via the
installer catalog (`virtexuplus58ga-family_xcux35_NAME=xcux35`).

## Usage

**1. Download** the AMD unified installer (Linux, full/offline) and note the
version. It's a plain **tar** (despite any `.tar.gz` name). Default expected
path: `/persist/software/vivado.<version>.tar` (override with
`VIVADO_INSTALLER_TAR`).

**2. Install to `/persist`** (device-limited, long, ~tens of GB):

```sh
nix run .#vivado-install
# then pack the result for the store:
VIVADO_PACK_TAR=/persist/software/vivado-2025.2-installed.tar nix run .#vivado-install
```

Env knobs: `VIVADO_INSTALLER_TAR`, `VIVADO_WORKDIR` (default
`/persist/tmp/vivado-extract`), `VIVADO_DEST` (default
`/persist/tmp/vivado-install`), `VIVADO_PACK_TAR`.

**3. Register the packed tree** in the store and record its hash:

```sh
nix-store --add-fixed sha256 /persist/software/vivado-2025.2-installed.tar
nix hash file /persist/software/vivado-2025.2-installed.tar   # -> sha256
```

Put that sha256 into `default.nix` (`installedTree.sha256`, marked `TODO`).

**4. Build & run:**

```sh
nix build .#vivado
nix run .#vivado                                   # GUI
nix shell .#vivado -c vivado -version
nix shell .#vivado -c bash -c \
  'cd <taxi>/src/eth/example/Alveo/fpga/fpga_X3522 && make'
```

The wrapper sources `settings64.sh`, so `vivado`/`vitis`/`xsct`/… are on PATH.

## Notes / caveats

- **nix-ld quirks handled by the tool:** NixOS has no `/bin/bash`, so the tool
  rewrites the installer's `#! /bin/bash` shebangs (anchored + idempotent; a
  broken `ldlibpath.sh` otherwise leaves `java.library.path` empty and the
  installer dies with `no xv_install in java.library.path`). `xsetup` also
  exits 0 even on failure, so the tool verifies the `vivado` binary exists.
  A benign `/bin/rm: No such file` warning during finalization is harmless.
- **FHS lib set** (`fhs-libs.nix`) is shared by the runtime wrapper and the
  install tool's `NIX_LD_LIBRARY_PATH`; missing-lib errors are a one-line add.
- **Disk:** the device-limited install is far smaller than the ~100 GB full ML
  install, but still sizeable — the installed tree lands in `/nix` (106 GB
  free). Bump the module set only as needed.
- **Bumping versions:** update `options.nix` (`version`, `installerDir`,
  `allModules` — regenerate the module list via `xsetup -b ConfigGen`), re-run
  the install, re-pack, update the sha.
