{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.codex.remote-control;
  inherit (pkgs.stdenv) isLinux;
  socketName = "codex-app-server/app-server.sock";

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
      index=0
      while (( index < ''${#args[@]} )); do
        arg="''${args[index]}"
        case "$arg" in
          -c | --config | --remote-auth-token-env | -i | --image | -m | --model | \
            -p | --profile | -s | --sandbox | -C | --cd | --add-dir | -a | \
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
      ${lib.optionalString isLinux ''
        if [[ -z "$endpoint" ]]; then
          runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          socket="$runtime_dir/${socketName}"

          if [[ ! -S "$socket" ]] && command -v systemctl >/dev/null 2>&1; then
            systemctl --user start codex-app-server.service >/dev/null 2>&1 || true
            for _ in {1..20}; do
              [[ -S "$socket" ]] && break
              ${pkgs.coreutils}/bin/sleep 0.05
            done
          fi

          [[ -S "$socket" ]] && endpoint="unix://$socket"
        fi
      ''}

      if [[ -n "$endpoint" ]]; then
        exec "$real_codex" --remote "$endpoint" "$@"
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

    systemd.user.services.codex-app-server = lib.mkIf (cfg.enable && isLinux) {
      Unit = {
        Description = "Persistent Codex app server";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };

      Service = {
        Type = "simple";
        RuntimeDirectory = "codex-app-server";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f %t/${socketName}";
        # One foreground process serves local/SSH-forwarded TUIs through the
        # private socket and registers with Codex's managed mobile relay.
        ExecStart = "${pkgs.codex}/bin/codex app-server --enable remote_control --listen unix://%t/${socketName}";
        ExecStopPost = "${pkgs.coreutils}/bin/rm -f %t/${socketName}";
        Restart = "always";
        RestartSec = 2;
      };

      Install.WantedBy = ["default.target"];
    };
  };
}
