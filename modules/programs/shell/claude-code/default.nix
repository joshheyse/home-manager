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
    # Read the key from the sops tmpfs file on demand instead of exporting
    # ANTHROPIC_API_KEY into the shell, where every child process inherits it.
    # Falls through to interactive /login if the file isn't present.
    apiKeyHelper = "cat ${config.home.homeDirectory}/.config/sops-nix/secrets/anthropic/api_key 2>/dev/null";
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

    ## Never Emit Secret Values
    **Absolute rule: never cause a secret value to appear in your output.**
    This is broader than "do not decrypt secrets" — a credential is usually
    already plaintext somewhere, and refusing to decrypt is no protection.

    Treat all of these as unreadable:
    - Decrypted secret files on disk (e.g. `/run/user/<uid>/secrets.d/...`,
      `~/.config/sops-nix/secrets/`, `.env`, `~/.aws/credentials`, `~/.netrc`).
      Reading these needs no key, so it is not "decryption" — it is still a leak.
    - Environment variables holding credentials, **including ones already set in
      your session**. You inherit them exactly as any other child process does;
      dumping them is precisely what credential-stealing malware does.
    - Values injected into a process at exec time by a wrapper.

    Never do any of the following:
    - `cat`/`head`/`grep` a file containing a live credential
    - Expand a secret-bearing variable. `''${VAR:-fallback}` prints the **value**
      when the variable is set; so do `''${VAR}`, `env`, `printenv`, and `set`.
    - Print a length, prefix, or "is it set" probe — `''${#VAR}` and
      `''${VAR:+yes}` are one typo away from `''${VAR:-yes}`, which prints it.
    - Rely on redaction. Piping through `sed`/`grep` to mask a value leaves the
      plaintext one mistake from output. There is no safe way to display it.

    **Verify by exit status, never by value:**
    - `test -r "$path"` to confirm a secret file is present
    - run the consuming command and check `$?`, e.g. `gh auth status >/dev/null 2>&1`
    - assert on configuration — rendered config, file mode, whether an export
      exists — rather than on the secret

    If a secret value does reach your output, stop, say so immediately, and tell
    the user to rotate that credential. Output is persisted to disk and sent to
    the API; it cannot be un-sent, and rotation is the only remedy.

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
    # We manage it as a mutable file via activation instead (Claude Code writes
    # settings.json at runtime, so it can't be a read-only store symlink).
    # home-manager 26.05 keys the upstream entry by its absolute path, so the
    # relative-key override alone no longer merges — suppress both spellings.
    file.".claude/settings.json".enable = lib.mkForce false;
    file."${config.home.homeDirectory}/.claude/settings.json".enable = lib.mkForce false;

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
