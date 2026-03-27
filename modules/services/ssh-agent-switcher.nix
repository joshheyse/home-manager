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
  switcherSocket = "/tmp/ssh-agent.${config.home.username}";
  # ssh-agent-switcher only matches socket names starting with "agent." or
  # containing ".sshd.".  Create a symlink with a compatible name so the
  # GPG agent SSH socket is discoverable.
  gpgAgentLink = "${homeDir}/.gnupg/agent.gpg-ssh";
  defaultAgentsDirs = "${homeDir}/.ssh/agent:/tmp";
  agentsDirs =
    if gpgEnabled
    then "${defaultAgentsDirs}:${homeDir}/.gnupg"
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
            if [ -e "${switcherSocket}" ]; then
              echo "Socket already exists"
              exit 1
            fi
            ${lib.optionalString gpgEnabled ''
              # Create symlink with agent.* name so ssh-agent-switcher can discover it.
              # Use gpgconf to get the correct socket path — on NixOS it's in
              # $XDG_RUNTIME_DIR/gnupg/, not ~/.gnupg/.
              ln -sf "$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)" "${gpgAgentLink}"
            ''}
          '';
        in "${preStart}";
        ExecStart = "${ssh-agent-switcher}/bin/ssh-agent-switcher --agents-dirs ${agentsDirs}";
        ExecStopPost = lib.mkIf gpgEnabled "${pkgs.coreutils}/bin/rm -f ${gpgAgentLink}";
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
      SSH_AUTH_SOCK = lib.mkForce switcherSocket;
    };

    # Also set in zsh init to override the value inherited from
    # gpg-agent-ssh.socket via the systemd/PAM environment, which is
    # already present before the shell starts.
    programs.zsh.initContent = lib.mkOrder 100 ''
      export SSH_AUTH_SOCK="${switcherSocket}"
    '';

    # Add the package to home.packages
    home.packages = [ssh-agent-switcher];
  };
}
