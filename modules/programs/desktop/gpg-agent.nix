{
  config,
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

  # Restore local gpg-agent socket after SSH session with GPG forwarding ends.
  # When SSH RemoteForward replaces the gpg-agent socket and then disconnects,
  # the socket file is removed. This detects that in local sessions and restarts
  # the gpg-agent socket unit so the local YubiKey works again.
  programs.zsh.initContent = lib.mkIf (config.services.gpg-agent.enable && pkgs.stdenv.isLinux) ''
    if [[ -z "$SSH_CONNECTION" && ! -S "$(gpgconf --list-dirs agent-socket)" ]]; then
      gpgconf --kill gpg-agent
      systemctl --user start gpg-agent.socket 2>/dev/null
    fi
  '';

  # Toggle between local gpg-agent and SSH-forwarded gpg-agent
  home.packages = lib.mkIf (config.services.gpg-agent.enable && pkgs.stdenv.isLinux) [
    (pkgs.writeShellScriptBin "gpg-local" ''
      # Switch to local gpg-agent (for when YubiKey is plugged into this machine)
      gpgconf --kill gpg-agent
      systemctl --user restart gpg-agent.socket gpg-agent-ssh.socket
      echo "Switched to local gpg-agent"
    '')
    (pkgs.writeShellScriptBin "gpg-remote" ''
      # Switch to SSH-forwarded gpg-agent (for when YubiKey is on the SSH client)
      # Requires an active SSH session with RemoteForward for the gpg-agent socket
      systemctl --user stop gpg-agent.socket gpg-agent-ssh.socket
      gpgconf --kill gpg-agent
      echo "Stopped local gpg-agent — SSH-forwarded agent will be used"
      echo "Reconnect your SSH session to bind the forwarded socket"
    '')
  ];
}
