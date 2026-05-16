{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.ssh-agent-switcher;
  ssh-agent-switcher = pkgs.callPackage ../../pkgs/ssh-agent-switcher {};
  gpgEnabled = config.services.gpg-agent.enable;
  homeDir = config.home.homeDirectory;
  # Socket and gpg compat symlink live under $XDG_RUNTIME_DIR — a tmpfs owned
  # mode 0700 by the user and wiped on logout by systemd-logind, so stale
  # sockets from an unclean shutdown can't lock the service out on next boot.
  # In systemd unit lines, %t expands to $XDG_RUNTIME_DIR.
  switcherSocketShell = "$XDG_RUNTIME_DIR/ssh-agent.sock";
  switcherSocketSystemd = "%t/ssh-agent.sock";
  # ssh-agent-switcher only matches socket names starting with "agent." or
  # containing ".sshd.".  Create a symlink with a compatible name so the
  # GPG agent SSH socket is discoverable.
  gpgAgentLinkSystemd = "%t/agent.gpg-ssh";
  defaultAgentsDirs = "${homeDir}/.ssh/agent:/tmp";
  agentsDirs =
    if gpgEnabled
    then "${defaultAgentsDirs}:%t"
    else defaultAgentsDirs;
in {
  options.services.ssh-agent-switcher = {
    enable = lib.mkEnableOption "SSH Agent Switcher service";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.ssh-agent-switcher = {
      Unit = {
        Description = "SSH Agent Switcher";
        After = lib.optionals gpgEnabled ["gpg-agent-ssh.socket"];
      };

      Service = {
        Type = "simple";
        ExecStartPre = let
          preStart = pkgs.writeShellScript "ssh-agent-switcher-pre" ''
            # Defensive cleanup for in-session restarts (e.g. crash + Restart=on-failure).
            # Cross-session staleness is handled by tmpfs wipe on logout.
            ${pkgs.coreutils}/bin/rm -f "$XDG_RUNTIME_DIR/ssh-agent.sock"
            ${lib.optionalString gpgEnabled ''
              # Create symlink with agent.* name so ssh-agent-switcher can discover it.
              # Use gpgconf to get the correct socket path — on NixOS it's in
              # $XDG_RUNTIME_DIR/gnupg/, not ~/.gnupg/.
              ${pkgs.coreutils}/bin/ln -sf "$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)" "$XDG_RUNTIME_DIR/agent.gpg-ssh"
            ''}
          '';
        in "${preStart}";
        ExecStart = "${ssh-agent-switcher}/bin/ssh-agent-switcher --socket-path ${switcherSocketSystemd} --agents-dirs ${agentsDirs}";
        ExecStopPost = "${pkgs.coreutils}/bin/rm -f ${switcherSocketSystemd}" + lib.optionalString gpgEnabled " ${gpgAgentLinkSystemd}";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = ["default.target"];
      };
    };

    # Override the SSH_AUTH_SOCK to use ssh-agent-switcher.
    # sessionVariables covers environment.d / new systemd user units.
    home.sessionVariables = {
      SSH_AUTH_SOCK = lib.mkForce switcherSocketShell;
    };

    # Also set in zsh init to override the value inherited from
    # gpg-agent-ssh.socket via the systemd/PAM environment, which is
    # already present before the shell starts.
    programs.zsh.initContent = lib.mkOrder 100 ''
      export SSH_AUTH_SOCK="${switcherSocketShell}"
    '';

    # Add the package to home.packages
    home.packages = [ssh-agent-switcher];
  };
}
