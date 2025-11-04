# Home Manager Modules

Portable Home Manager modules, custom packages, and overlays for use across multiple machines (personal and work).

## Overview

This repository provides a self-contained set of Home Manager configurations that can be used as a flake input. It includes:

- **Home Manager modules** - Shell programs, desktop applications, and services
- **Custom packages** - `ssh-agent-switcher` and `ssh-fzf`
- **Overlays** - Version overrides (e.g., claude-code)
- **Secrets** - GPG/YubiKey public keys

## Usage

### As a Flake Input

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";

    # Add this repository as an input
    home-modules = {
      url = "github:yourusername/home-manager";  # Update with your repo URL
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {nixpkgs, home-manager, home-modules, ...}: {
    homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = [home-modules.overlays.default];
      };

      modules = [
        home-modules.homeManagerModules.default
        {
          home.username = "user";
          home.homeDirectory = "/home/user";
        }
      ];
    };
  };
}
```

### Using Individual Modules

For more granular control, import specific modules:

```nix
modules = [
  home-modules.homeManagerModules.base          # Base settings
  home-modules.homeManagerModules.shell         # Shell programs (zsh, tmux, etc.)
  home-modules.homeManagerModules.desktop       # Desktop apps (kitty, yabai, etc.)
  home-modules.homeManagerModules.ssh-agent-switcher  # SSH agent service
];
```

### Using Custom Packages

Access custom packages in your configuration:

```nix
home.packages = [
  home-modules.packages.${system}.ssh-agent-switcher
  home-modules.packages.${system}.ssh-fzf
];
```

Or reference them directly in modules that already use `pkgs.callPackage`.

## Structure

```
.
├── flake.nix                    # Flake exposing modules, packages, and overlays
├── modules/                     # Home Manager modules
│   ├── base.nix                 # Base configuration
│   ├── programs/
│   │   ├── shell/               # Shell tools (zsh, tmux, fzf, git, etc.)
│   │   └── desktop/             # Desktop apps (kitty, yabai, sketchybar, etc.)
│   └── services/
│       └── ssh-agent-switcher.nix
├── pkgs/                        # Custom package definitions
│   ├── ssh-agent-switcher/
│   └── ssh-fzf/
├── overlays/                    # Package overlays
│   └── claude-code.nix
└── secrets/                     # Public keys (safe to share)
    └── yubikey.pub
```

## Modules Included

### Base (`base.nix`)
- Home Manager state version
- Session variables (SHELL, SSH_AUTH_SOCK)
- Systemd user service management (Linux only)

### Shell Programs (`programs/shell`)
- **Zsh** - Shell with extensive git aliases and antidote plugins
- **Tmux** - Terminal multiplexer with Tokyo Night theme
- **Starship** - Custom prompt
- **Fzf** - Fuzzy finder with Dracula theme
- **Git** - Git configuration with GPG signing
- **Neovim** - Text editor
- **Bat, Eza, Fd, Ripgrep** - Modern CLI replacements
- **Btop, Bottom** - System monitors
- **Lazygit** - Git TUI
- **Direnv** - Directory-specific environments
- **GPG** - GPG/YubiKey configuration

### Desktop Programs (`programs/desktop`)
- **Kitty** - Terminal emulator (macOS/Linux)
- **Yabai** - Tiling window manager (macOS)
- **Sketchybar** - Status bar (macOS)
- **Raycast** - Launcher (macOS)
- **GPG Agent** - GPG agent with SSH support

### Services
- **ssh-agent-switcher** - Systemd service for SSH agent management (Linux)

## Custom Packages

### ssh-agent-switcher
A tool for managing SSH agent sockets across multiple SSH agents (gpg-agent, 1Password, etc.).

### ssh-fzf
Fuzzy finder integration for SSH hosts from your SSH config.

## Requirements

- Nix with flakes enabled
- Home Manager (release-25.05)
- nixpkgs release-25.05

## License

This is personal configuration code. Use at your own discretion.
