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

- Uses nixpkgs release 25.05
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

## Custom Packages

Packages in `/pkgs/` are custom-built utilities. When adding new packages:

1. Create a directory in `/pkgs/` with a `default.nix`
2. Follow Nix package conventions (meta, src, buildInputs, etc.)
3. Export the package in `flake.nix` outputs.packages
4. Test with `nix build .#packageName`

Current packages:
- **ssh-agent-switcher**: Utility for switching SSH agents
- **ssh-fzf**: Fuzzy finder for SSH connections

## Custom Overlays

Overlays in `/overlays/` modify package definitions. Currently includes:

- `claude-code.nix`: Updates claude-code to specific version

When creating new overlays:
1. Create a `.nix` file in `/overlays/`
2. Follow the existing pattern (final: prev: {...})
3. Export in `flake.nix` outputs.overlays
4. Consuming flakes can apply with `nixpkgs.overlays = [ inputs.home-manager.overlays.overlayName ];`

## Security

- **SOPS Secrets**: This repository may contain encrypted secrets in `/secrets/`
  - **IMPORTANT**: You (Claude) are NEVER allowed to decrypt sops secret files
  - You can read the structure and understand the configuration
  - You cannot and must not attempt to decrypt or access secret values
