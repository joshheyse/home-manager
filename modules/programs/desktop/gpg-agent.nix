{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isLinux;
  gpgEnabled = config.services.gpg-agent.enable && isLinux;
  hyprlandEnabled = config.programs.hyprland-desktop.enable or false;

  # Reusable script to restore local gpg-agent (works from any context:
  # systemd, Hyprland exec-once, hypridle unlock hook, manual invocation).
  # Uses full paths so it doesn't depend on PATH.
  gpgLocalScript = pkgs.writeShellScript "gpg-local" ''
    ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent
    ${pkgs.systemd}/bin/systemctl --user restart gpg-agent.socket gpg-agent-ssh.socket
  '';

  # Monitor script that watches for GPG socket deletion and auto-restores
  # the local agent after SSH disconnect removes the forwarded socket.
  gpgAgentMonitorScript = pkgs.writeShellScript "gpg-agent-monitor" ''
    SOCKET="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-socket)"
    SOCKET_DIR="$(dirname "$SOCKET")"

    restore_local() {
      if [ ! -S "$SOCKET" ]; then
        ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent
        ${pkgs.systemd}/bin/systemctl --user restart gpg-agent.socket gpg-agent-ssh.socket 2>/dev/null
      fi
    }

    # Check on startup in case socket is already missing
    restore_local

    # Watch for socket deletion events and restore when needed
    while ${pkgs.inotify-tools}/bin/inotifywait -qq -e delete -e delete_self "$SOCKET_DIR"; do
      sleep 1 # let SSH potentially bind a forwarded socket before we replace it
      restore_local
    done
  '';
in {
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
      else pkgs.pinentry-rofi;
    extraConfig = ''
      debug-level advanced
      log-file /tmp/gpg-agent.log
    '';
  };

  # Restore local gpg-agent socket after SSH session with GPG forwarding ends.
  # When SSH RemoteForward replaces the gpg-agent socket and then disconnects,
  # the socket file is removed. This detects that in local sessions and restarts
  # the gpg-agent socket unit so the local YubiKey works again.
  # Kept as defense-in-depth fallback alongside the systemd monitor service.
  programs.zsh.initContent = lib.mkIf gpgEnabled ''
    if [[ -z "$SSH_CONNECTION" && ! -S "$(gpgconf --list-dirs agent-socket)" ]]; then
      gpgconf --kill gpg-agent
      systemctl --user start gpg-agent.socket 2>/dev/null
    fi
  '';

  # Toggle between local gpg-agent and SSH-forwarded gpg-agent
  home.packages = lib.mkIf gpgEnabled [
    (pkgs.writeShellScriptBin "gpg-local" ''
      ${gpgLocalScript}
      echo "Switched to local gpg-agent"
    '')
    (pkgs.writeShellScriptBin "gpg-remote" ''
      # Switch to SSH-forwarded gpg-agent (for when YubiKey is on the SSH client)
      # Requires an active SSH session with RemoteForward for the gpg-agent socket
      ${pkgs.systemd}/bin/systemctl --user stop gpg-agent.socket gpg-agent-ssh.socket
      ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent
      echo "Stopped local gpg-agent — SSH-forwarded agent will be used"
      echo "Reconnect your SSH session to bind the forwarded socket"
    '')
    (pkgs.writeShellApplication {
      name = "agent-check";
      runtimeInputs = with pkgs; [gnupg openssh coreutils systemd];
      text = builtins.readFile ./agent-check.sh;
    })
  ];

  # Restore local GPG agent on Hyprland login (user is at the desk)
  wayland.windowManager.hyprland.settings.exec-once =
    lib.mkIf (gpgEnabled && hyprlandEnabled) ["${gpgLocalScript}"];

  # Restore local GPG agent on hyprlock unlock (user returned to desk)
  services.hypridle.settings.general.unlock_cmd =
    lib.mkIf (gpgEnabled && hyprlandEnabled) (toString gpgLocalScript);

  # Monitor GPG agent socket and auto-restore after SSH disconnect.
  # When SSH with GPG forwarding disconnects, it removes the socket file.
  # This service detects the deletion via inotifywait and restarts the
  # local gpg-agent socket units within ~1 second.
  systemd.user.services.gpg-agent-monitor = lib.mkIf gpgEnabled {
    Unit.Description = "Monitor GPG agent socket and auto-restore after SSH disconnect";
    Service = {
      Type = "simple";
      ExecStart = toString gpgAgentMonitorScript;
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = ["default.target"];
  };
}
