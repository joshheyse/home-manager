{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.sops.userSecrets;

  # Single source of truth for shared user secrets: sops key -> env var name.
  # Use null for secrets that are only ever read from disk by path.
  #
  # Nothing here is exported into the login shell. Secrets reach programs one
  # of three ways, in order of preference:
  #   1. the program takes a file path (digitalblasphemy -> --api-token-file)
  #   2. a wrapper injects it into that one process (gh, kicad-parts)
  #   3. `with-secrets <group> -- cmd`, or `load-secrets <group>` interactively
  #
  # Rationale: commodity infostealers dump the whole environment in one shot,
  # so an exported secret is harvested by any child process. A secret that only
  # exists inside the process that needs it is not in that dump. This raises the
  # cost of opportunistic theft; it is not a boundary against a same-user
  # attacker, who can read the tmpfs files directly.
  #
  # Keys are validated against the sops file at build time: sops-nix runs
  # `sops-install-secrets -check-mode=sopsfile` in the manifest's checkPhase
  # (validateSopsFiles defaults to true), so a key missing from the yaml
  # fails the build rather than activation.
  secretEnv = {
    "digikey/clientId" = "DIGIKEY_CLIENT_ID";
    "digikey/clientSecret" = "DIGIKEY_CLIENT_SECRET";
    "github/token" = "GH_TOKEN";
    "anthropic/api_key" = "ANTHROPIC_API_KEY";
    "openai/api_key" = "OPENAI_API_KEY";
    "openrouter/api_key" = "OPENROUTER_API_KEY";
    "databento/api_key" = "DATABENTO_API_KEY";
    # Read by path from the hyprland wallpaper service.
    "digitalblasphemy/api_key" = null;
  };

  injectable = lib.filterAttrs (_: envVar: envVar != null) secretEnv;

  groupOf = name: builtins.head (lib.splitString "/" name);
  groups = lib.unique (map groupOf (lib.attrNames injectable));
  groupList = lib.concatStringsSep " " groups;

  # One case arm per group: load each of its secrets, and record the variable
  # names so --print can re-emit them without duplicating this mapping.
  caseArms = lib.concatStrings (map (
      group: let
        inGroup = lib.filterAttrs (name: _: groupOf name == group) injectable;
        loads = lib.concatStrings (lib.mapAttrsToList (
            name: envVar: let
              path = lib.escapeShellArg config.sops.secrets.${name}.path;
            in ''
              if [[ -r ${path} ]]; then
                ${envVar}="$(cat ${path})"
                export ${envVar}
                vars+=(${envVar})
              else
                echo "with-secrets: ${name} is not readable at ${path}" >&2
                missing=1
              fi
            ''
          )
          inGroup);
      in ''
        ${group})
        ${loads}  ;;
      ''
    )
    groups);

  withSecrets = pkgs.writeShellApplication {
    name = "with-secrets";
    text = ''
      # Inject sops secrets into a single command's environment, so they never
      # sit in the ambient shell environment where any child process sees them.
      #   with-secrets databento -- python script.py
      #   eval "$(with-secrets --print databento)"   # load into current shell
      print_only=0
      missing=0
      wanted=()
      vars=()

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --print) print_only=1; shift ;;
          --) shift; break ;;
          -h | --help)
            echo "usage: with-secrets [--print] <group>... [-- <command>...]"
            echo "groups: ${groupList}"
            exit 0 ;;
          -*)
            echo "with-secrets: unknown flag '$1'" >&2
            exit 2 ;;
          *) wanted+=("$1"); shift ;;
        esac
      done

      if [[ ''${#wanted[@]} -eq 0 ]]; then
        echo "with-secrets: no secret group given (have: ${groupList})" >&2
        exit 2
      fi

      for group in "''${wanted[@]}"; do
        case "$group" in
      ${caseArms}
          *)
            echo "with-secrets: unknown group '$group' (have: ${groupList})" >&2
            exit 2 ;;
        esac
      done

      [[ $missing -eq 0 ]] || exit 1

      if [[ $print_only -eq 1 ]]; then
        for var in "''${vars[@]}"; do
          printf 'export %s=%q\n' "$var" "''${!var-}"
        done
        exit 0
      fi

      if [[ $# -eq 0 ]]; then
        echo "with-secrets: no command given (use -- before the command)" >&2
        exit 2
      fi
      exec "$@"
    '';
  };
  exportLine = name: let
    path = lib.escapeShellArg config.sops.secrets.${name}.path;
  in ''
    if [[ -r ${path} ]]; then
      export ${injectable.${name}}="$(cat ${path})"
    fi
  '';
in {
  options.sops.userSecrets = {
    enable = lib.mkEnableOption "shared user sops secrets";

    exportToShell = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames injectable));
      default = [];
      example = ["databento/api_key"];
      description = ''
        sops keys whose values are exported into the interactive shell.

        Empty by default, and it should stay that way unless a tool genuinely
        needs the value ambient: an exported secret is inherited by every child
        process, which is exactly what environment-scraping malware harvests.
        Prefer `with-secrets <group> -- cmd` or a wrapper. Listing a key here is
        a deliberate, per-host exception to that rule.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Shared user secret declarations.
    # Each host must also set:
    #   - sops.defaultSopsFile (path to secrets yaml, from root flake)
    #   - sops.gnupg.home (macOS only, to override the age default)
    sops.secrets = lib.genAttrs (lib.attrNames secretEnv) (_: {});

    # User-level age key for decryption (separate from the system key).
    # On NixOS, system sops provisions this to /run/secrets/ (tmpfs) at boot.
    # macOS hosts that use gnupg should override with sops.gnupg.home.
    sops.age.keyFile = lib.mkIf pkgs.stdenv.isLinux "/run/secrets/josh_age_key";

    home.packages = [withSecrets];

    # Deliberate, per-invocation load into the *current* shell. Deliberately not
    # run at startup: that would recreate the ambient exposure this avoids.
    programs.zsh.initContent = lib.mkAfter ''
      # bash
      load-secrets() {
        eval "$(${lib.getExe withSecrets} --print "$@")"
      }
      ${lib.concatStrings (map exportLine cfg.exportToShell)}
    '';
  };
}
