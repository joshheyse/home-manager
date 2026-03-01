{
  config,
  pkgs,
  ...
}: let
  gpgKeyId = "0x06B3614378AFA59E";
in {
  # GPG/YubiKey configuration
  programs.gpg = {
    enable = true;
    # Disabled due to conflicts with Homebrew GPG installation
    # Import key manually with: gpg --import /nix/store/.../yubikey.pub
    publicKeys = [
      {
        source = ../../../../secrets/yubikey.pub;
        trust = 5;
      }
    ];
    settings = {
      use-agent = true;
      throw-keyids = true;
      default-key = gpgKeyId;
      trusted-key = gpgKeyId;
      no-greeting = true;
    };
    scdaemonSettings = {
      disable-ccid = false;
    };
  };

  home = {
    # Use GPG agent for SSH (YubiKey support)
    sessionVariables = {
      SSH_AUTH_SOCK = "$HOME/.gnupg/S.gpg-agent.ssh";
    };

    # Configure SSH authentication via GPG
    file.".gnupg/sshcontrol".text = ''
      # Authentication subkey keygrip for SSH
      015B64C5064DC1FEE3E6CCF5BF4C9374F3DDF06B
    '';

    # Ensure GPG directory structure exists before importing keys
    activation.initGpgDirs = config.lib.dag.entryBefore ["importGpgKeys"] ''
      $DRY_RUN_CMD mkdir -p $HOME/.gnupg/public-keys.d
      $DRY_RUN_CMD chmod 700 $HOME/.gnupg/public-keys.d
    '';

    # GPG testing script
    packages = [
      (pkgs.writeShellScriptBin "gpg-rt" ''
        echo "test message" | gpg --encrypt --recipient ${gpgKeyId} | gpg --decrypt
      '')
    ];
  };
}
