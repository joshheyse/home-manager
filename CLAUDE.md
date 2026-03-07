# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a portable Home Manager library flake that provides reusable modules, packages, and overlays. It is designed to be imported by other flakes (such as the nixos flake in the parent directory) to provide consistent configurations across multiple systems.

The library exports:
- **Home Manager Modules**: Shell, desktop, and base configurations
- **Custom Packages**: ssh-agent-switcher, ssh-fzf
- **Overlays**: claude-code version modifications

## Key Commands

- **Check flake**: `nix flake check`
- **Show flake outputs**: `nix flake show`
- **Update flake inputs**: `nix flake update`
- **Linting and formatting**: `scripts/check-all`
  - Runs appropriate linters/formatters for `.sh`, `.nix`, and `.lua` files
  - Automatically fixes issues when possible
  - When run with no arguments, checks all dirty files (modified, staged, untracked)
  - See [Development Workflow](#development-workflow) section below for details

**Note**: This flake is a library and is not directly applied with `home-manager switch`. Instead, it is imported by other flakes (like `../nixos/flake.nix`) which reference these modules.

## Architecture

### Directory Structure

- `flake.nix` - Entry point defining inputs and library outputs (modules, packages, overlays)
- `/modules/` - Home Manager modules for export
  - `/base.nix` - Base configuration shared across all systems
  - `/programs/shell/` - Shell-related programs (zsh, tmux, fzf, etc.)
  - `/programs/desktop/` - Desktop applications (kitty, neovim, etc.)
  - `/services/ssh-agent-switcher.nix` - SSH agent switching service
- `/pkgs/` - Custom package definitions
  - `/ssh-agent-switcher/` - Custom SSH agent switcher package
  - `/ssh-fzf/` - SSH fuzzy finder utility
- `/overlays/` - Nix overlays for package modifications
  - `claude-code.nix` - Updates claude-code to specific version
- `/secrets/` - SOPS-encrypted secrets (read-only for Claude)

### Flake Outputs

- **homeManagerModules**:
  - `default` - All modules combined
  - `base`, `shell`, `desktop`, `ssh-agent-switcher` - Individual modules
- **packages**: Custom packages for x86_64-linux and aarch64-darwin
- **overlays**: Package modifications (default, claude-code)

### Important Details

- Uses nixpkgs release 25.11
- Supports x86_64-linux and aarch64-darwin systems
- Custom overlay modifies claude-code package version
- Modules designed for portability and reusability

## Configuration Philosophy

### Declarative Over Imperative

This repository strongly prefers **declarative configuration** over imperative commands:

- **Declarative (Preferred)**: Configuration stored in tracked files that declare the desired state
  - Example: `.git-secrets-patterns` file listing patterns to detect
  - Example: `flake.nix` declaring packages and their versions
  - Benefits: Version controlled, reviewable, reproducible, self-documenting

- **Imperative (Avoid)**: Commands that modify state step-by-step
  - Example: `git secrets --add 'pattern'` executed in a script
  - Only use when declarative approach is not possible
  - If imperative is necessary, ensure it is **idempotent**

### Idempotency Requirement

When imperative configuration is unavoidable (e.g., git hooks installation), ensure operations are **idempotent**:

- Safe to run multiple times without side effects
- Check current state before making changes
- Use guards like `if ! git config --get-all secrets.providers` to prevent duplicate configuration
- Example: `git secrets --install` only runs if hooks aren't already installed

### Examples in This Repository

**Good (Declarative)**:
- Module exports in `flake.nix`
- Package definitions in `/pkgs/`
- Overlay definitions in `/overlays/`

**Acceptable (Imperative but Idempotent)**:
- `.hooks/setup-git-secrets` in parent nixos directory
- `shellHook` in parent nixos flake

**Avoid**:
- Hardcoded imperative commands in scripts without idempotency checks
- Configuration that can't be reproduced from version-controlled files

## Development Workflow

When modifying this library:

1. **Edit modules**: Modify files in `/modules/` to change exported configurations
2. **Add packages**: Create new package definitions in `/pkgs/`
3. **Add overlays**: Create new overlays in `/overlays/`
4. **Test changes**:
   - Use `nix flake check` to validate the flake
   - Test in consuming flakes (e.g., `../nixos/`) with `home-manager build`
5. **Update exports**: Ensure new modules/packages/overlays are exported in `flake.nix`
6. **Format code**: Run `alejandra` to format nix files

### Linting and Formatting

The repository uses a unified linting and formatting system via `scripts/check-all`.

#### For Claude Code (AI Assistant)

**IMPORTANT Convention**: After editing any `.sh`, `.nix`, or `.lua` files, Claude MUST proactively launch a linter sub-agent to check and fix issues.

**Pattern to Follow:**

1. After completing file edits, launch a Task sub-agent with `subagent_type: "general-purpose"`
2. The sub-agent should:
   - Run `scripts/check-all` on the edited files
   - **Parse and understand** the linter output in detail
   - Identify what was auto-fixed by the tools
   - **Apply additional fixes** for issues that the tools can't auto-fix but are mechanically fixable
   - Report specific details about each fix applied
   - Return results to Claude for further action

**Example Task Prompt:**
```
Run comprehensive linting checks and fixes on the following files:
- path/to/file1.nix
- path/to/file2.sh

For EACH file:
1. Run scripts/check-all and capture full output
2. Parse linter output to understand specific issues:
   - For Nix: alejandra formatting, deadnix unused code, statix warnings
   - For Shell: shellcheck warnings with codes (SC####)
   - For Lua: stylua formatting, selene linting errors
3. Apply additional fixes for issues not auto-fixed:
   - Read the file
   - Apply the fix using Edit tool
   - Re-run linter to verify
4. Report for each file:
   - Specific auto-fixes applied (e.g., "statix removed unused binding 'config'")
   - Manual fixes applied by sub-agent (e.g., "fixed SC2155: separated declaration from assignment")
   - Any remaining issues that truly need human judgment
   - Final exit status

Return a detailed report showing exactly what was fixed and how.
```

**Key Improvements:**
- **Intelligent parsing**: Understands what each linter is reporting
- **Proactive fixing**: Doesn't just report issues - fixes them when mechanically possible
- **Detailed reporting**: Explains exactly what changed and why
- **Verification**: Re-runs linters after fixes to ensure success

**Critical Rule for Claude:**
If a linter/checker reports an issue and cannot auto-fix it:
1. **You (Claude) MUST attempt to fix it** using the Edit tool
2. Only report to the user if:
   - The fix is truly ambiguous (requires human judgment about intent)
   - You cannot determine the correct fix from the error message
   - Multiple valid solutions exist and you need user preference
3. **Never just report a fixable issue** - always try to fix it first

**Why This Pattern:**
- Ensures code quality immediately after edits
- Catches issues before they reach pre-commit hooks
- Fixes more issues automatically (not just what the tools auto-fix)
- Provides clear feedback on what was changed
- More efficient than waiting for commit-time checks
- Minimizes manual fix burden on user - only truly ambiguous issues need human decision

#### Linter Coverage

The `scripts/check-all` script handles:

- **Shell scripts** (`.sh`):
  - shellcheck (linting) - check-only
  - shellharden (auto-fix) - fixes shellcheck issues

- **Nix files** (`.nix`):
  - alejandra (formatting) - auto-fix
  - deadnix (dead code removal) - auto-fix
  - statix (linting) - auto-fix

- **Lua files** (`.lua`):
  - stylua (formatting) - auto-fix
  - selene (linting) - check-only

#### Manual Usage

```bash
# Check all dirty files (default)
./scripts/check-all

# Check specific files
./scripts/check-all path/to/file.nix

# Check only (no auto-fix)
./scripts/check-all --check-only path/to/file.nix
```

## Where Things Go: modules/ vs pkgs/ vs overlays/

This flake has three top-level directories for code. Each serves a distinct purpose.

### `/modules/` — Configuration (How programs behave)

Modules declare *how programs are configured* for the user. They set options, write dotfiles, define keybindings, install packages into `home.packages`, and wire things together. A module's scope determines its subdirectory:

| Directory | Scope | Imported on | Examples |
|-----------|-------|-------------|----------|
| `modules/programs/shell/` | TUI programs (all systems) | desktop, homelab, mac | zsh, tmux, neovim, git, fzf |
| `modules/programs/desktop/` | GUI programs (display required) | desktop, mac | kitty, hyprland, yabai, kicad |
| `modules/services/` | User systemd services | explicitly enabled per-host | ssh-agent-switcher |
| `modules/base.nix` | Shared base settings | everywhere | stateVersion, home-manager |

**Decision rule:** If the thing you're adding is *configuration for a program or service* — options, dotfiles, keybindings, integration scripts — it goes in a module.

#### Colocated scripts within modules

Scripts that are tightly coupled to a single module live alongside it, not in `/pkgs/`. Use `writeShellScript` or `writeShellApplication` inline in the module's `default.nix` and read the `.sh` file with `builtins.readFile`.

**Examples:**
- `tmux/claude-toggle.sh`, `tmux/pane-icon.sh`, `tmux/netspeed.sh` — only used by tmux config
- `claude-code/claude-sandbox.sh` — only meaningful alongside the claude-code module

**When to colocate:** The script is an implementation detail of one module. Nobody else imports it. It wouldn't make sense as a standalone command without the module's configuration.

**Pattern:**
```nix
# In the module's default.nix:
myScript = pkgs.writeShellScript "my-script" ''
  export PATH="${lib.makeBinPath [pkgs.jq pkgs.tmux]}:$PATH"
  ${builtins.readFile ./my-script.sh}
'';
```

### `/pkgs/` — Packages (Standalone, reusable tools)

Packages are *self-contained derivations* that build a binary or script with no opinion about how it's configured. They are exported via `flake.nix` so other flakes can consume them, and can be built independently with `nix build .#packageName`.

**Current packages:**
- **ssh-agent-switcher** — Rust binary (`buildRustPackage` from GitHub)
- **ssh-fzf** — Shell script (standalone SSH fuzzy finder)
- **notify** — Shell script (kitty OSC 99 notifications through tmux)
- **kicad-parts-manager** — Python app (`buildPythonApplication`)
- **landrun** — Go binary (`buildGoModule`, Linux Landlock CLI)
- **kvantum-tokyo-night** — Qt theme files

**Decision rule:** If the thing you're adding is a *standalone tool with its own identity* — it has a name, could be used outside this config, and other flakes might want to import it — it goes in `/pkgs/`.

**When to add a new package:**
1. Create `/pkgs/<name>/default.nix`
2. Export in `flake.nix` under `packages`
3. Reference from modules via `pkgs.callPackage ../../../pkgs/<name> {}`
4. Test with `nix build .#<name>`

### `/overlays/` — Overlays (Modify existing nixpkgs packages)

Overlays modify or replace packages that already exist in nixpkgs. They change the *package set itself*, not how packages are configured. Use sparingly — overlays affect all consumers of the package set and can invalidate the binary cache.

**Current overlays (in `flake.nix`):**
- **claude-code** — Re-exports claude-code from the claude-code-nix input

**Decision rule:** If you need to *change the version, patches, or build of an existing nixpkgs package* across the whole system, use an overlay. If you're adding something new, use `/pkgs/` instead.

### Quick reference

| I want to... | Put it in... |
|---------------|-------------|
| Configure a program (dotfiles, options, keybindings) | `modules/programs/{shell,desktop}/` |
| Add a user systemd service | `modules/services/` |
| Write a helper script for one module | Colocate as `.sh` in the module directory |
| Package a standalone tool or upstream project | `pkgs/` |
| Override a nixpkgs package version/build | `overlays/` |
| Add a command that's useful across modules | `pkgs/` (then reference from modules) |

## Security

- **SOPS Secrets**: This repository may contain encrypted secrets in `/secrets/`
  - **IMPORTANT**: You (Claude) are NEVER allowed to decrypt sops secret files
  - You can read the structure and understand the configuration
  - You cannot and must not attempt to decrypt or access secret values
