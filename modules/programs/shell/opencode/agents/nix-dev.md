---
description: Nix work in a multi-host NixOS + home-manager monorepo. Modules, hosts, packages, sops secrets.
model: anthropic/claude-opus-4-7
temperature: 0.1
mode: primary
---

You are working in a Nix flake monorepo that owns multiple NixOS hosts plus a portable home-manager library exposed as a sub-flake under `home-manager/`. The user runs the system themselves and prefers declarative, reproducible configuration.

Layout:

- `modules/nixos/` — system-level NixOS modules (run as root; set `services.*`, `boot.*`, `networking.*`, `hardware.*`).
- `home-manager/modules/` — user-level home-manager modules (manage dotfiles, user services, user packages). Sub-flake with its own `flake.nix`.
- `hosts/<host>/` — per-host NixOS wiring (`configuration.nix`, `disko.nix`, `hardware-configuration.nix`).
- `home-manager/flake.nix:hostModules.<host>` — per-host home-manager module composition.
- `home-manager/pkgs/`, `home-manager/overlays/` — standalone packages and nixpkgs overrides.
- `secrets/hosts/<host>/`, `secrets/shared/`, `secrets/users/<user>/` — sops-encrypted yaml.

Conventions:

- Format Nix with alejandra. Lint with deadnix and statix.
- Shell: shellcheck + shellharden. Lua: stylua + selene.
- After editing `.nix` / `.sh` / `.lua`, run `home-manager/scripts/check-all <files>`.
- Sops-nix manages secrets. Never decrypt them. Never put plaintext keys in Nix files.
- Declarative over imperative. When imperative is unavoidable, make it idempotent.

Behavior:

- Before adding a module option or wrapper, check whether an existing module or upstream nixpkgs module already covers it. Wrappers for their own sake are churn.
- Follow the project's "where things go" matrix. NixOS modules ≠ home-manager modules. Programs go in `modules/programs/`, system services in `modules/nixos/services/`, standalone tools in `pkgs/`, package overrides in `overlays/`.
- Prefer native systemd via upstream NixOS modules over hand-rolled podman containers when an upstream option exists. If you do reach for podman, match the pattern of the existing container-based services in the repo.
- Hosts with impermanence enabled reset `/` on boot. State directories must register with `environment.persistence."/persist".directories`.
- macOS hosts use nix-darwin + standalone home-manager. NixOS modules do not apply there; don't suggest they will.
- Match existing module style (typed options, `mkEnableOption`, hardened systemd units, `lib.mkIf cfg.enable {...}`). Don't introduce new patterns when the repo already has one.

Workflow:

- `hms` runs `home-manager switch` for the current host.
- Remote NixOS deploys: `nixos-rebuild switch --flake .#<host> --target-host <host> --use-remote-sudo` from the local checkout. Don't ssh in and rebuild remotely — the flake doesn't exist on the remote.
- Validate changes with `nix flake check` or `nix build --no-link --dry-run .#nixosConfigurations.<host>.config.system.build.toplevel` before applying.

Don't:

- Don't add `Co-Authored-By` lines to commits.
- Don't decrypt sops files.
- Don't `git add` files you weren't asked to commit.
- Don't suggest disabling security features (e.g. `--no-verify`, removing auth) as a shortcut around an obstacle. Find the root cause.
