{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.sops.userSecrets;
in {
  options.sops.userSecrets.enable = lib.mkEnableOption "shared user sops secrets";

  config = lib.mkIf cfg.enable {
    # Shared user secret declarations.
    # Each host must also set:
    #   - sops.defaultSopsFile (path to secrets yaml, from root flake)
    #   - sops.gnupg.home (macOS only, to override the age default)
    sops.secrets = {
      "digikey/clientId" = {};
      "digikey/clientSecret" = {};
      "github/token" = {};
      "anthropic/api_key" = {};
    };

    # User-level age key for decryption (separate from the system key).
    # macOS hosts that use gnupg should override with sops.gnupg.home.
    sops.age.keyFile =
      if pkgs.stdenv.isDarwin
      then "/Users/joshheyse/.config/sops/age/keys.txt"
      else "/home/josh/.config/sops/age/keys.txt";

    # Export secrets as environment variables
    programs.zsh.initContent = lib.mkAfter ''
      # bash
      if [[ -r "$HOME/.config/sops-nix/secrets/digikey/clientId" ]]; then
        export DIGIKEY_CLIENT_ID="$(cat "$HOME/.config/sops-nix/secrets/digikey/clientId")"
      fi
      if [[ -r "$HOME/.config/sops-nix/secrets/digikey/clientSecret" ]]; then
        export DIGIKEY_CLIENT_SECRET="$(cat "$HOME/.config/sops-nix/secrets/digikey/clientSecret")"
      fi
      if [[ -r "$HOME/.config/sops-nix/secrets/github/token" ]]; then
        export GITHUB_TOKEN="$(cat "$HOME/.config/sops-nix/secrets/github/token")"
      fi
      if [[ -r "$HOME/.config/sops-nix/secrets/anthropic/api_key" ]]; then
        export ANTHROPIC_API_KEY="$(cat "$HOME/.config/sops-nix/secrets/anthropic/api_key")"
      fi
    '';
  };
}
