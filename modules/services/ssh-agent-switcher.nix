{
  config,
  pkgs,
  lib,
  ...
}: let
  ssh-agent-switcher = pkgs.callPackage ../../pkgs/ssh-agent-switcher {};
in {
  systemd.user.services.ssh-agent-switcher = {
    Unit = {
      Description = "SSH Agent Switcher";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      Type = "simple";
      ExecStart = "${ssh-agent-switcher}/bin/ssh-agent-switcher";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '[ ! -e \"/tmp/ssh-agent.${config.home.username}\" ]'";
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
}
