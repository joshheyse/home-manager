{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isLinux;
  gpgEnabled = config.services.gpg-agent.enable && isLinux;
  hyprlandEnabled = config.programs.hyprland-desktop.enable or false;

  # Shared guard: a shell function `remote_session_active` that succeeds (0)
  # when any logind session is a remote SSH login. Such a session owns the
  # forwarded gpg-agent socket (mapped onto the standard socket path via SSH
  # RemoteForward), so the local agent must NOT be restored while it is up —
  # doing so clobbers the forward. Reused by every local-restore path so the
  # guard is defined in exactly one place. Uses full paths (no PATH reliance).
  remoteSessionActiveFn = ''
    remote_session_active() {
      local sid
      while read -r sid _; do
        [ -n "$sid" ] || continue
        if [ "$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p Remote --value 2>/dev/null)" = yes ]; then
          return 0
        fi
      done < <(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null)
      return 1
    }
  '';

  # Reusable script to restore the local gpg-agent (works from any context:
  # systemd, Hyprland exec-once, hypridle unlock hook, manual invocation).
  # Uses full paths so it doesn't depend on PATH.
  #
  # Skips while a remote SSH session owns the forwarded socket, UNLESS invoked
  # with `--force` (the manual `gpg-local` command, where the user explicitly
  # wants the local card regardless of any open SSH session).
  #
  # `gpgconf --kill gpg-agent` blocks until its internal timeout when the
  # socket file exists but no agent is bound to it (stale socket left by an
  # SSH RemoteForward disconnect). Only kill when a real agent is alive, and
  # always sweep the socket files so socket activation can rebind cleanly.
  gpgLocalScript = pkgs.writeShellScript "gpg-local" ''
    ${remoteSessionActiveFn}
    SOCKET="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-socket)"
    SSH_SOCKET="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)"
    if [ "''${1:-}" != "--force" ] && remote_session_active; then
      exit 0
    fi
    if ${pkgs.procps}/bin/pgrep -u "$USER" -x gpg-agent >/dev/null 2>&1; then
      ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent 2>/dev/null || true
    fi
    rm -f "$SOCKET" "$SSH_SOCKET"
    ${pkgs.systemd}/bin/systemctl --user restart gpg-agent.socket gpg-agent-ssh.socket
  '';

  # Monitor script that watches for GPG socket deletion and auto-restores
  # the local agent after SSH disconnect removes the forwarded socket.
  #
  # Probes with `gpg-connect-agent --no-autostart /bye` instead of just
  # checking `[ -S ]`, so a stale socket file (exists but unbound) is also
  # detected. `--no-autostart` is essential: a bare probe would itself spawn a
  # local `gpg-agent --daemon`, which is exactly the rogue agent that clobbers
  # the forward. Also wakes every 30s to catch stale sockets that were never
  # explicitly deleted (some SSH cleanup paths leave the file behind).
  #
  # Skips restoring the local agent while a remote (SSH) login session is
  # active. Local mode is restored on disconnect, once the last remote session
  # is gone. With `no-autostart` set globally, this monitor is the authority
  # that re-listens the socket units, so it must stay robust.
  gpgAgentMonitorScript = pkgs.writeShellScript "gpg-agent-monitor" ''
    ${remoteSessionActiveFn}
    SOCKET="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-socket)"
    SSH_SOCKET="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)"
    SOCKET_DIR="$(${pkgs.coreutils}/bin/dirname "$SOCKET")"

    restore_local() {
      # An agent (local or forwarded) is answering — nothing to do. Probe with
      # --no-autostart so the check itself never spawns a competing agent.
      if ${pkgs.coreutils}/bin/timeout 2 ${pkgs.gnupg}/bin/gpg-connect-agent --no-autostart /bye >/dev/null 2>&1; then
        return
      fi
      # A remote SSH session owns the forwarded socket — don't clobber it.
      if remote_session_active; then
        return
      fi
      if ${pkgs.procps}/bin/pgrep -u "$USER" -x gpg-agent >/dev/null 2>&1; then
        ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent 2>/dev/null || true
      fi
      rm -f "$SOCKET" "$SSH_SOCKET"
      ${pkgs.systemd}/bin/systemctl --user restart gpg-agent.socket gpg-agent-ssh.socket 2>/dev/null
    }

    # Check on startup in case socket is already missing/stale
    restore_local

    # Watch for socket deletion AND wake periodically to catch stale sockets
    # that were never explicitly deleted.
    while :; do
      ${pkgs.inotify-tools}/bin/inotifywait -qq -t 30 -e delete -e delete_self "$SOCKET_DIR" >/dev/null 2>&1 || true
      ${pkgs.coreutils}/bin/sleep 1 # let SSH potentially bind a forwarded socket before we replace it
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
    # On Linux we override HM's zsh integration below to add `--no-autostart`
    # to the `updatestartuptty` call, so a desktop shell can't spawn a rogue
    # local agent that clobbers the forwarded socket. macOS keeps HM's default
    # integration (it relies on gpg autostart — no systemd socket activation).
    enableZshIntegration = lib.mkIf isLinux false;
    pinentry.package =
      if pkgs.stdenv.isDarwin
      then pkgs.pinentry_mac
      else pkgs.pinentry-rofi;
    extraConfig = ''
      debug-level advanced
      log-file /tmp/gpg-agent.log
    '';
  };

  # Never let `gpg` autostart a competing local agent. With socket activation
  # (at the desk) or the SSH RemoteForward (when remote) always providing the
  # agent on the standard socket path, autostart only ever spawns the rogue
  # `gpg-agent --daemon` that clobbers the forward. Linux/agent-enabled only —
  # macOS relies on autostart (no systemd socket activation).
  programs.gpg.settings.no-autostart = lib.mkIf gpgEnabled true;

  # Replaces HM's zsh integration (disabled above on Linux). Exports GPG_TTY
  # and runs `updatestartuptty` with `--no-autostart` so a desktop shell can't
  # spawn a local agent over the forwarded socket. Also a defense-in-depth
  # fallback: on a local (non-SSH) shell whose agent socket has gone missing,
  # restore the local agent — but never while a remote SSH session owns the
  # forwarded socket.
  programs.zsh.initContent = lib.mkIf gpgEnabled ''
    export GPG_TTY=$TTY
    ${pkgs.gnupg}/bin/gpg-connect-agent --quiet --no-autostart updatestartuptty /bye > /dev/null 2>&1 || true

    if [[ -z "$SSH_CONNECTION" && ! -S "$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-socket)" ]]; then
      _gpg_remote_active=
      while read -r _sid _; do
        [[ -n "$_sid" ]] || continue
        if [[ "$(${pkgs.systemd}/bin/loginctl show-session "$_sid" -p Remote --value 2>/dev/null)" == yes ]]; then
          _gpg_remote_active=1
          break
        fi
      done < <(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null)
      if [[ -z "$_gpg_remote_active" ]]; then
        ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent
        ${pkgs.systemd}/bin/systemctl --user start gpg-agent.socket 2>/dev/null
      fi
      unset _gpg_remote_active _sid
    fi
  '';

  # Toggle between local gpg-agent and SSH-forwarded gpg-agent
  home.packages = lib.mkIf gpgEnabled [
    (pkgs.writeShellScriptBin "gpg-local" ''
      # --force: switch to the local card even if an SSH session is open.
      ${gpgLocalScript} --force
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
