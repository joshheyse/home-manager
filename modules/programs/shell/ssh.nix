_: {
  programs.ssh = {
    enable = true;

    matchBlocks = {
      "github.com" = {
        user = "git";
        identityFile = "~/.ssh/id_rsa_yubikey.pub";
      };
    };
  };

  # Export GPG auth subkey as SSH public key for IdentityFile matching
  home.file.".ssh/id_rsa_yubikey.pub".source = ../../../secrets/id_rsa_yubikey.pub;
}
