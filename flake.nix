{
  description = "Portable Home Manager modules, packages, and overlays";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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
    sidra = {
      url = "github:wimpysworld/sidra";
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
    sidra,
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
        }
        ({pkgs, ...}: {
          home.packages = nixpkgs.lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") (
            # Rebuild claude-desktop's FHS env with docker_29. Upstream pins
            # `docker` (= nixpkgs default 28.x, now insecure/unmaintained) in its
            # targetPkgs and builds the FHS in its own pkgs instance, so our
            # permittedInsecurePackages can't reach it. Faithfully replicate the
            # small upstream FHS (k3d3/claude-desktop-linux-flake) with docker_29.
            let
              # nodePackages.asar was removed from nixpkgs in 26.05 (now top-level
              # pkgs.asar). Upstream k3d3/claude-desktop-linux-flake still lists
              # nodePackages.asar in nativeBuildInputs, which throws under our pinned
              # 26.05 nixpkgs. Replace the whole list (same inputs, new asar attr) so
              # the throwing alias is never forced.
              cd = claude-desktop.packages.x86_64-linux.claude-desktop.overrideAttrs (_: {
                nativeBuildInputs = with pkgs; [p7zip asar makeWrapper imagemagick icoutils perl];
              });
            in [
              (pkgs.buildFHSEnv {
                name = "claude-desktop";
                targetPkgs = p: with p; [docker_29 glibc openssl nodejs uv];
                runScript = "${cd}/bin/claude-desktop";
                extraInstallCommands = ''
                  mkdir -p $out/share/applications
                  cp ${cd}/share/applications/claude.desktop $out/share/applications/
                  mkdir -p $out/share/icons
                  cp -r ${cd}/share/icons/* $out/share/icons/
                '';
              })
            ]
          );
          sops = {
            userSecrets.enable = true;
            defaultSopsFile = ./secrets/users/josh/secrets.yaml;
          };
        })
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
        ./modules/programs/shell/opencode/mac.nix
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

      # x86_64 Linux dev VM (OrbStack on Apple Silicon with Rosetta).
      # Reuses the headless `homelab` module set — shell tools only,
      # no desktop/Wayland — and overrides username to match the
      # default user OrbStack provisions inside the VM.
      #
      # ssh-agent-switcher is disabled here because OrbStack already
      # forwards the macOS SSH agent into the VM and sets
      # SSH_AUTH_SOCK. The switcher only watches ~/.ssh/agent/ and
      # /tmp/agent.* — OrbStack's socket isn't in either — so leaving
      # it on hijacks SSH_AUTH_SOCK and breaks agent access entirely.
      "joshheyse@orb-x64" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          localSystem = "x86_64-linux";
          config.allowUnfree = true;
          overlays = [self.overlays.default];
        };
        modules =
          hostModules.homelab
          ++ [
            {
              home = {
                username = "joshheyse";
                homeDirectory = "/home/joshheyse";
              };
              services.ssh-agent-switcher.enable = nixpkgs.lib.mkForce false;
            }
          ];
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
        dwfv = pkgs.callPackage ./pkgs/dwfv {};
        notify = pkgs.callPackage ./pkgs/notify {};
        jupyter-bridge = pkgs.callPackage ./pkgs/jupyter-bridge {};
        kicad-parts-manager = pkgs.callPackage ./pkgs/kicad-parts-manager {};
        kvantum-tokyo-night = pkgs.callPackage ./pkgs/kvantum-tokyo-night {};
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
        landrun = pkgs.callPackage ./pkgs/landrun {};
        db-wallpaper = pkgs.callPackage ./pkgs/db-wallpaper {};
        portable-ssh = pkgs.callPackage ./pkgs/portable-ssh {};
      });

    # Shared nix-darwin modules
    darwinModules = {
      default = ./modules/darwin;
    };

    # Overlays
    overlays = {
      default = final: _prev: let
        # Local packages, exposed via the overlay so modules can write
        # `pkgs.portable-ssh` instead of doing relative path walks back
        # to this flake's `pkgs/` directory. The flake is the only place
        # that knows the layout — modules stay layout-independent.
        localPkgs = self.packages.${final.system} or {};
      in {
        inherit (claude-code-nix.packages.${final.system}) claude-code;
        # sidra.packages is only populated on x86_64-linux and aarch64-darwin.
        # The inherit is lazy: aarch64-linux only errors if pkgs.sidra is read.
        inherit (sidra.packages.${final.system} or {}) sidra;
        inherit
          (localPkgs)
          ssh-agent-switcher
          ssh-fzf
          dwfv
          notify
          jupyter-bridge
          kicad-parts-manager
          kvantum-tokyo-night
          ;
        # Linux-only packages: inherit lazily so darwin doesn't error
        # unless something actually reads them.
        inherit (localPkgs) landrun db-wallpaper portable-ssh;
      };
      claude-code = final: _prev: {
        inherit (claude-code-nix.packages.${final.system}) claude-code;
      };
      sidra = final: _prev: {
        inherit (sidra.packages.${final.system} or {}) sidra;
      };
    };
  };
}
