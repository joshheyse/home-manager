{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.codex.remote-control;
  inherit (pkgs.stdenv) isLinux;
  codexHome = "${config.home.homeDirectory}/.codex";
  standaloneRoot = "${codexHome}/packages/standalone";
  standaloneCodex = "${standaloneRoot}/current/codex";
  standaloneBin = "${standaloneRoot}/bin";

  # Remote Control intentionally requires the self-updating standalone Codex
  # installation. Pin the bootstrap logic while allowing that installation's
  # own updater to manage releases beneath ~/.codex/packages/standalone.
  standaloneInstaller = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/openai/codex/rust-v0.146.0/scripts/install/install.sh";
    hash = "sha256-upLdJ+XAbw07vFi/pLnPtlmc0nQvux+SonZebAfe21o=";
  };

  bootstrapStandalone = pkgs.writeShellApplication {
    name = "codex-remote-control-bootstrap";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnutar
    ];
    text = ''
      if [[ -x ${lib.escapeShellArg standaloneCodex} ]]; then
        exit 0
      fi

      export CODEX_HOME=${lib.escapeShellArg codexHome}
      export CODEX_INSTALL_DIR=${lib.escapeShellArg standaloneBin}
      export CODEX_NON_INTERACTIVE=1
      export PATH="${standaloneBin}:$PATH"
      exec ${pkgs.dash}/bin/dash ${standaloneInstaller}
    '';
  };

  codexWrapped = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = lib.optionals isLinux [pkgs.systemd];
    text = ''
      real_codex=${lib.escapeShellArg "${pkgs.codex}/bin/codex"}

      # Explicit remote selection belongs to the caller. Do not add a second
      # endpoint or otherwise reinterpret management/noninteractive commands.
      for arg in "$@"; do
        case "$arg" in
          --remote | --remote=*) exec "$real_codex" "$@" ;;
        esac
      done

      # `--remote` connects the TUI, not every Codex subcommand. Find the first
      # positional argument after global options so plain prompts plus the
      # resume/fork TUIs use the persistent server, while exec, review, login,
      # app-server administration, and similar commands remain local.
      args=("$@")
      command=""
      has_cwd_override=false
      index=0
      while (( index < ''${#args[@]} )); do
        arg="''${args[index]}"
        case "$arg" in
          -C | --cd)
            has_cwd_override=true
            ((index += 2))
            ;;
          --cd=*)
            has_cwd_override=true
            ((index += 1))
            ;;
          -c | --config | --remote-auth-token-env | -i | --image | -m | --model | \
            -p | --profile | -s | --sandbox | --add-dir | -a | \
            --ask-for-approval)
            ((index += 2))
            ;;
          --*=* | -*)
            ((index += 1))
            ;;
          *)
            command="$arg"
            break
            ;;
        esac
      done

      case "$command" in
        "" | resume | fork) ;;
        exec | e | review | login | logout | mcp | plugin | mcp-server | \
          app-server | remote-control | completion | update | doctor | sandbox | \
          debug | apply | archive | delete | unarchive | cloud | exec-server | \
          features | help)
          exec "$real_codex" "$@"
          ;;
        *) ;;
      esac

      if [[ "''${CODEX_REMOTE_AUTOCONNECT:-1}" == 0 ]]; then
        exec "$real_codex" "$@"
      fi

      endpoint="''${CODEX_REMOTE_ENDPOINT:-}"

      if [[ -n "$endpoint" ]]; then
        if [[ "$has_cwd_override" == true ]]; then
          exec "$real_codex" --remote "$endpoint" "$@"
        fi
        exec "$real_codex" --remote "$endpoint" --cd "$PWD" "$@"
      fi

      # A failed/not-yet-ready service must never make the CLI unusable.
      exec "$real_codex" "$@"
    '';
  };
in {
  options.programs.codex.remote-control.enable =
    lib.mkEnableOption "persistent Codex app-server and automatic TUI connection";

  config = {
    home.packages = [
      (
        if cfg.enable
        then codexWrapped
        else pkgs.codex
      )
    ];

    systemd.user.services.codex-remote-control-bootstrap = lib.mkIf (cfg.enable && isLinux) {
      Unit = {
        Description = "Bootstrap the Codex Remote Control runtime";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };

      Service = {
        Type = "oneshot";
        UMask = "0077";
        ExecStart = "${bootstrapStandalone}/bin/codex-remote-control-bootstrap";
        RemainAfterExit = true;
      };

      Install.WantedBy = ["default.target"];
    };

    systemd.user.services.codex-remote-control = lib.mkIf (cfg.enable && isLinux) {
      Unit = {
        Description = "Codex Remote Control";
        After = ["codex-remote-control-bootstrap.service"];
        Requires = ["codex-remote-control-bootstrap.service"];
      };

      Service = {
        Type = "oneshot";
        UMask = "0077";
        # The high-level `remote-control start` command exits non-zero when the
        # initial relay connection is unavailable. systemd then tears down the
        # detached children in the unit cgroup, including the local control
        # socket. Bootstrap only waits for the durable local daemon; that daemon
        # owns relay reconnection and remains available for pairing/diagnostics.
        ExecStart = "${standaloneCodex} app-server daemon bootstrap --remote-control";
        ExecStop = "${standaloneCodex} app-server daemon stop";
        RemainAfterExit = true;
      };

      Install.WantedBy = ["default.target"];
    };
  };
}
