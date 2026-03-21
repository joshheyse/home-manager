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
  # ssh-agent-switcher only matches socket names starting with "agent." or
  # containing ".sshd.".  Create a symlink with a compatible name so the
  # GPG agent SSH socket is discoverable.
  gpgAgentLink = "${homeDir}/.gnupg/agent.gpg-ssh";
  gpgAgentSocket = "${homeDir}/.gnupg/S.gpg-agent.ssh";
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
        After =
          ["graphical-session.target"]
          ++ lib.optionals gpgEnabled ["gpg-agent-ssh.socket"];
        PartOf = ["graphical-session.target"];
      };

      Service = {
        Type = "simple";
        ExecStartPre = let
          preStart = pkgs.writeShellScript "ssh-agent-switcher-pre" ''
            if [ -e "/tmp/ssh-agent.${config.home.username}" ]; then
              echo "Socket already exists"
              exit 1
            fi
            ${lib.optionalString gpgEnabled ''
              # Create symlink with agent.* name so ssh-agent-switcher can discover it
              ln -sf "${gpgAgentSocket}" "${gpgAgentLink}"
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

    # Override the SSH_AUTH_SOCK to use ssh-agent-switcher
    home.sessionVariables = {
      SSH_AUTH_SOCK = lib.mkForce "/tmp/ssh-agent.${config.home.username}";
    };

    # Add the package to home.packages
    home.packages = [ssh-agent-switcher];
  };
}
