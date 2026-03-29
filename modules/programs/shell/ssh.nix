{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;

  envType = lib.types.submodule {
    options = {
      user = lib.mkOption {
        type = lib.types.str;
        description = "Default remote username for hosts in this environment.";
      };
      uid = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "Default remote UID for hosts in this environment (used for GPG socket path).";
      };
      hosts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            hostname = lib.mkOption {
              type = lib.types.str;
              description = "IP or hostname of the remote machine.";
            };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Override the environment-level user for this host.";
            };
            uid = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "Override the environment-level UID for this host.";
            };
          };
        });
        default = {};
        description = "Hosts in this environment.";
      };
    };
  };

  cfg = config.programs.ssh;

  # Local GPG extra socket path (what we forward FROM)
  localGpgExtra =
    if isDarwin
    then "${config.home.homeDirectory}/.gnupg/S.gpg-agent.extra"
    else "/run/user/${toString localUid}/gnupg/S.gpg-agent.extra";

  inherit (cfg) localUid;

  # Generate matchBlocks for a single host within an environment
  mkHostBlocks = envDefaults: name: hostCfg: let
    user =
      if hostCfg.user != null
      then hostCfg.user
      else envDefaults.user;
    uid =
      if hostCfg.uid != null
      then hostCfg.uid
      else envDefaults.uid;
    remoteGpgSocket = "/run/user/${toString uid}/gnupg/S.gpg-agent";
  in {
    # Full config: YubiKey + agent forwarding + GPG forwarding + tmux
    ${name} = {
      inherit user;
      inherit (hostCfg) hostname;
      forwardAgent = true;
      identityFile = "~/.ssh/id_rsa_yubikey.pub";
      remoteForwards = [
        {
          bind.address = remoteGpgSocket;
          host.address = localGpgExtra;
        }
      ];
      extraOptions = {
        StreamLocalBindUnlink = "yes";
        RequestTTY = "force";
        RemoteCommand = "zsh -l -c \"exec tmux new -A -s main\"";
      };
    };

    # Raw config: just YubiKey auth
    "${name}-raw" = {
      inherit user;
      inherit (hostCfg) hostname;
      identityFile = "~/.ssh/id_rsa_yubikey.pub";
    };
  };

  # Generate all matchBlocks from all environments
  generatedBlocks =
    lib.foldl' (
      acc: env:
        acc
        // lib.foldl' (
          innerAcc: name:
            innerAcc // mkHostBlocks env name env.hosts.${name}
        ) {}
        (builtins.attrNames env.hosts)
    ) {}
    cfg.remoteEnvironments;
in {
  options.programs.ssh.localUid = lib.mkOption {
    type = lib.types.int;
    default = 1000;
    description = "Local user UID (used for GPG socket path on Linux).";
  };

  options.programs.ssh.remoteEnvironments = lib.mkOption {
    type = lib.types.listOf envType;
    default = [];
    description = "List of remote environments with default user/uid and host definitions.";
  };

  config.programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks =
      {
        "*" = {
          serverAliveInterval = lib.mkDefault 15;
          serverAliveCountMax = lib.mkDefault 2;
        };
        "github.com" = {
          user = lib.mkDefault "git";
          identityFile = lib.mkDefault "~/.ssh/id_rsa_yubikey.pub";
        };
      }
      // generatedBlocks;
  };

  # Export GPG auth subkey as SSH public key for IdentityFile matching
  config.home.file.".ssh/id_rsa_yubikey.pub".source = ../../../secrets/id_rsa_yubikey.pub;
}
