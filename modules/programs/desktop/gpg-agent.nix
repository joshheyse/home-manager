{
  lib,
  pkgs,
  ...
}: {
  # GPG Agent configuration with SSH support
  # Disabled by default - override in host-specific config if needed
  services.gpg-agent = {
    enable = lib.mkDefault false;
    enableSshSupport = true;
    defaultCacheTtl = 60;
    maxCacheTtl = 120;
    pinentry.package =
      if pkgs.stdenv.isDarwin
      then pkgs.pinentry_mac
      else pkgs.pinentry-gnome3;
    extraConfig = ''
      debug-level advanced
      log-file /tmp/gpg-agent.log
    '';
  };
}
