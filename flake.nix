{
  description = "Portable Home Manager modules, packages, and overlays";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.05";
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    claude-code-nix,
    ...
  }: let
    # Define systems
    systems = ["x86_64-linux" "aarch64-darwin"];

    # Helper to generate attribute sets for each system
    forEachSystem = f: nixpkgs.lib.genAttrs systems f;
  in {
    # Home Manager modules that can be imported
    homeManagerModules = {
      # Default module exports everything
      default = {
        imports = [
          ./modules/base.nix
          ./modules/programs/shell
          ./modules/programs/desktop
          ./modules/services/ssh-agent-switcher.nix
        ];
      };

      # Individual module exports for granular control
      base = ./modules/base.nix;
      shell = ./modules/programs/shell;
      desktop = ./modules/programs/desktop;
      ssh-agent-switcher = ./modules/services/ssh-agent-switcher.nix;
    };

    # Custom packages
    packages = forEachSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      ssh-agent-switcher = pkgs.callPackage ./pkgs/ssh-agent-switcher {};
      ssh-fzf = pkgs.callPackage ./pkgs/ssh-fzf {};
      notify = pkgs.callPackage ./pkgs/notify {};
      kicad-parts-manager = pkgs.callPackage ./pkgs/kicad-parts-manager {};
    });

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
