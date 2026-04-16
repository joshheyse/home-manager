{
  pkgs,
  lib,
  config,
  ...
}: let
  jsonFormat = pkgs.formats.json {};
  cfg = config.programs.claude-code;

  # Our managed settings (sandbox, permissions, plugins).
  # Other modules (e.g. tmux) can still set programs.claude-code.settings.hooks —
  # we merge everything together and manage it via activation instead of home.file.
  ownSettings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    sandbox = {
      enabled = true;
      autoAllowBashIfSandboxed = true;
      allowUnsandboxedCommands = true;
      excludedCommands = ["ssh" "git" "gh"];
      network = {
        allowedDomains = ["*"];
        allowLocalBinding = false;
      };
    };
    permissions = {
      allow = [
        "WebFetch"
        "WebSearch"
        "Edit"
        "Write"
        "Bash"
      ];
      deny = [
        "Bash(rm -rf /*:*)"
        "Bash(rm -rf /:*)"
        "Bash(chmod -R 777:*)"
        "Bash(curl * | bash:*)"
        "Bash(curl * | sh:*)"
        "Bash(wget * | bash:*)"
        "Bash(wget * | sh:*)"
      ];
    };
    enabledPlugins = {
      "clangd-lsp@claude-plugins-official" = true;
    };
  };

  # Merge our settings with anything other modules contributed via
  # programs.claude-code.settings (e.g. hooks from the tmux module)
  managedSettings = lib.recursiveUpdate cfg.settings ownSettings;
  managedSettingsFile = jsonFormat.generate "claude-code-managed-settings.json" managedSettings;

  managedMemoryFile = pkgs.writeText "claude-code-CLAUDE.md" ''
    # Global Claude Code Instructions

    ## Git Commits
    - Never add a `Co-Authored-By` line to commit messages

    ## Evidence and Epistemic Discipline
    When analyzing a problem, do not present guesses as facts.
    Follow these rules:
    1. **Separate evidence from inference**
      - First state the directly observed evidence.
      - Then state what you infer from that evidence.
      - Mark any inference that is not directly verified.
    2. **Do not claim a root cause unless it is supported**
      - Never say or imply "this is happening because X" unless X is established by the available evidence.
      - If multiple explanations fit the facts, list the leading hypotheses and explain what would distinguish them.
    3. **Check available evidence sources before concluding**
      - Before giving a diagnosis, inspect the tools, logs, files, error messages, metrics, traces, configs, or other available sources relevant to the problem.
      - If you have not checked them, say so explicitly.
    4. **Use calibrated language**
      - Use phrases like:
        - "The evidence shows..."
        - "One plausible explanation is..."
        - "I cannot verify that yet from the available information."
        - "This is a hypothesis, not a confirmed cause."
      - Avoid phrases like:
        - "This is definitely because..."
        - "The issue is caused by..."
        - "Clearly..."
        unless the evidence actually proves it.
    5. **Prefer disconfirmation over story-building**
      - Actively look for facts that would falsify your current explanation.
      - Before settling on a diagnosis, ask: "What evidence would make this explanation wrong?"
    6. **If evidence is insufficient, say so**
      - It is better to say "I do not have enough evidence to determine the cause" than to provide a confident but weak explanation.
      - When uncertain, recommend the next highest-value check.
    7. **Give conclusions with confidence levels**
      - Label conclusions as:
        - Confirmed
        - Strongly supported
        - Tentative
        - Speculative
    8. **Do not optimize for sounding decisive**
      - Optimize for being correct, transparent, and falsifiable.
      - Intellectual honesty is more important than fluency.

  '';
in {
  programs.claude-code = {
    enable = true;
    # Don't set settings or memory here — we manage them via activation
  };

  home = {
    # Prevent the upstream module from creating home.file for settings.json.
    # We manage it as a mutable file via activation instead.
    file.".claude/settings.json".enable = lib.mkForce false;

    packages =
      lib.optionals pkgs.stdenv.isLinux [pkgs.bubblewrap pkgs.socat];

    activation.claude-code-mutable-config = lib.hm.dag.entryAfter ["writeBoundary"] ''
      claude_dir="${config.home.homeDirectory}/.claude"
      settings="$claude_dir/settings.json"
      memory="$claude_dir/CLAUDE.md"
      managed="${managedSettingsFile}"

      # Ensure directory exists
      mkdir -p "$claude_dir"

      # Settings: deep-merge nix-managed keys over any existing runtime settings.
      # Runtime keys (like theme) are preserved; nix-managed keys always win.
      if [ -f "$settings" ] && [ ! -L "$settings" ]; then
        # Existing mutable file — merge managed keys on top
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" "$managed" > "$settings.tmp"
        mv "$settings.tmp" "$settings"
      else
        # First run or was a symlink from previous home-manager generation — seed from managed
        rm -f "$settings"
        cp "$managed" "$settings"
        chmod 644 "$settings"
      fi


      # CLAUDE.md: overwrite with managed content (this is declarative intent,
      # not user-edited — user memory goes in ~/.claude/projects/*/memory/)
      rm -f "$memory"
      cp "${managedMemoryFile}" "$memory"
      chmod 644 "$memory"
    '';
  };
}
