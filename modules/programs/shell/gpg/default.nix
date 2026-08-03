{
  config,
  pkgs,
  ...
}: let
  gpgKeyId = "0x06B3614378AFA59E";
  inherit (pkgs.stdenv) isDarwin;
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
    # macOS: route scdaemon through the system PC/SC service instead of
    # its built-in CCID/libusb driver. macOS's com.apple.ctkpcscd claims
    # the CCID interface, so the internal driver fails with "Operation not
    # supported by device" (card appears absent -> "insert card" prompts).
    # pcsc-shared avoids exclusive-lock contention with ykman/other PC/SC
    # clients. On Linux the internal CCID driver works, so keep it there.
    scdaemonSettings =
      if isDarwin
      then {
        disable-ccid = true;
        pcsc-shared = true;
      }
      else {
        disable-ccid = false;
      };
  };

  home = {
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

    # GPG testing script and YubiKey provisioning dependencies
    packages = [
      pkgs.expect
      (pkgs.writeShellScriptBin "gpg-rt" ''
        echo "test message" | gpg --encrypt --recipient ${gpgKeyId} | gpg --decrypt
      '')
    ];
  };
}
