{
  description = "Portable Home Manager modules, packages, and overlays";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    claude-code-nix,
    claude-desktop,
    sops-nix,
    ...
  }: let
    # Define systems
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

    # Helper to generate attribute sets for each system
    forEachSystem = f: nixpkgs.lib.genAttrs systems f;

    # Per-host module lists — single source of truth for both standalone
    # hms and NixOS-integrated home-manager.
    hostModules = {
      desktop = [
        self.homeManagerModules.base
        self.homeManagerModules.shell
        self.homeManagerModules.desktop
        self.homeManagerModules.ssh-agent-switcher
        self.homeManagerModules.secrets
        sops-nix.homeManagerModules.sops
        {
          home = {
            username = nixpkgs.lib.mkDefault "josh";
            homeDirectory = nixpkgs.lib.mkDefault "/home/josh";
          };
          services = {
            ssh-agent-switcher.enable = true;
            gpg-agent.enable = true;
            udiskie.enable = true;
          };
          programs = {
            hyprland-desktop.enable = true;
            hyprland-desktop.wallpaper.enable = true;
            tiling-wm.enable = true;
            screenshots.enable = true;
            firefox-profile.enable = false;
          };
          programs.ssh.remoteEnvironments = [
            {
              user = "josh";
              uid = 1000;
              hosts = {
                homelab = {hostname = "192.168.1.66";};
              };
            }
          ];
          home.packages = [
            claude-desktop.packages.x86_64-linux.claude-desktop-with-fhs
          ];
          sops = {
            userSecrets.enable = true;
            defaultSopsFile = ./secrets/users/josh/secrets.yaml;
          };
        }
      ];

      homelab = [
        self.homeManagerModules.base
        self.homeManagerModules.shell
        self.homeManagerModules.ssh-agent-switcher
        {
          home = {
            username = nixpkgs.lib.mkDefault "josh";
            homeDirectory = nixpkgs.lib.mkDefault "/home/josh";
          };
          services.ssh-agent-switcher.enable = true;
        }
      ];

      mac = [
        self.homeManagerModules.default
        self.homeManagerModules.secrets
        sops-nix.homeManagerModules.sops
        {
          home = {
            username = nixpkgs.lib.mkForce "joshheyse";
            homeDirectory = nixpkgs.lib.mkForce "/Users/joshheyse";
          };
          services = {
            ssh-agent-switcher.enable = false;
            gpg-agent.enable = true;
          };
          programs = {
            tiling-wm.enable = true;
            firefox-profile.enable = false;
            raycast.enable = true;
            screenshots.enable = true;
          };
          programs.ssh.remoteEnvironments = [
            {
              user = "josh";
              uid = 1000;
              hosts = {
                homelab = {hostname = "192.168.1.66";};
                desktop = {hostname = "desktop";};
                dev = {hostname = "desktop";};
              };
            }
          ];
          sops = {
            userSecrets.enable = true;
            gnupg.home = "/Users/joshheyse/.gnupg";
            defaultSopsFile = ./secrets/users/josh/secrets.yaml;
          };
        }
      ];
    };
  in {
    # Home Manager modules that can be imported
    homeManagerModules = {
      # Default module exports everything
      default = {
        imports = [
          ./modules/theme.nix
          ./modules/base.nix
          ./modules/programs/shell
          ./modules/programs/desktop
          ./modules/services/ssh-agent-switcher.nix
        ];
      };

      # Individual module exports for granular control
      theme = ./modules/theme.nix;
      base = ./modules/base.nix;
      shell = ./modules/programs/shell;
      desktop = ./modules/programs/desktop;
      ssh-agent-switcher = ./modules/services/ssh-agent-switcher.nix;
      secrets = ./modules/secrets.nix;
    };

    # Per-host module lists (consumed by both hms and nix/flake.nix)
    inherit hostModules;

    # Standalone homeConfigurations for hms
    homeConfigurations = {
      "josh@desktop" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          localSystem = "x86_64-linux";
          config.allowUnfree = true;
          overlays = [self.overlays.default];
        };
        modules = hostModules.desktop;
      };

      "josh@homelab" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          localSystem = "x86_64-linux";
          config.allowUnfree = true;
          overlays = [self.overlays.default];
        };
        modules = hostModules.homelab;
      };

      "joshheyse@macbook-pro" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          localSystem = "aarch64-darwin";
          config.allowUnfree = true;
          overlays = [self.overlays.default];
        };
        modules = hostModules.mac;
      };
    };

    # Custom packages
    packages = forEachSystem (system: let
      pkgs = import nixpkgs {
        localSystem = system;
        config.allowUnfree = true;
      };
    in
      {
        ssh-agent-switcher = pkgs.callPackage ./pkgs/ssh-agent-switcher {};
        ssh-fzf = pkgs.callPackage ./pkgs/ssh-fzf {};
        notify = pkgs.callPackage ./pkgs/notify {};
        jupyter-bridge = pkgs.callPackage ./pkgs/jupyter-bridge {};
        kicad-parts-manager = pkgs.callPackage ./pkgs/kicad-parts-manager {};
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
        landrun = pkgs.callPackage ./pkgs/landrun {};
        db-wallpaper = pkgs.callPackage ./pkgs/db-wallpaper {};
      });

    # Shared nix-darwin modules
    darwinModules = {
      default = ./modules/darwin;
    };

    # Overlays
    overlays = {
      default = final: _prev: {
        inherit (claude-code-nix.packages.${final.system}) claude-code;
      };
      claude-code = final: _prev: {
        inherit (claude-code-nix.packages.${final.system}) claude-code;
      };
    };
  };
}
