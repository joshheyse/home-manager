{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  config = lib.mkIf isDarwin {
    # Raycast is installed via home.packages in desktop/default.nix

    # Post-activation script to configure Raycast
    # Note: Some Raycast settings can only be configured through the app itself
    home.activation.configureRaycast = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Disable Spotlight's Cmd+Space hotkey to allow Raycast to use it
      # This requires running: System Settings > Keyboard > Keyboard Shortcuts > Spotlight
      # and unchecking "Show Spotlight search"

      # Note: We cannot fully automate Raycast configuration as it stores settings
      # in binary plists and requires first-run setup through the app.
      #
      # Manual setup required after first launch:
      # 1. Open Raycast (should be in Applications)
      # 2. Go to Raycast Settings (Cmd+,)
      # 3. Under "General" > "Raycast Hotkey" > Set to "Cmd+Space"
      # 4. Under "Appearance" > Choose dark theme (closest to Tokyo Night)
      # 5. Under "Extensions" > Enable desired extensions:
      #    - File Search (built-in)
      #    - Applications (built-in)
      #    - Window Management (built-in)
      #    - Clipboard History (optional)
      #    - Calculator (optional)
      # 6. System Settings > Keyboard > Keyboard Shortcuts > Spotlight
      #    Uncheck "Show Spotlight search" to free up Cmd+Space

      $DRY_RUN_CMD echo "Raycast installed. Manual configuration required - see raycast.nix comments."
    '';

    # Create a setup helper script
    home.file.".config/raycast/setup-instructions.md" = {
      text = ''
        # Raycast Setup Instructions

        ## Required Manual Steps

        ### 1. Disable Spotlight Cmd+Space Hotkey
        1. Open **System Settings**
        2. Navigate to **Keyboard** > **Keyboard Shortcuts** > **Spotlight**
        3. Uncheck "Show Spotlight search"

        ### 2. Configure Raycast
        1. Launch Raycast (Cmd+Space should work after disabling Spotlight)
        2. Open Raycast Settings: **Cmd+,**

        #### General Settings
        - **Raycast Hotkey**: Set to **Cmd+Space**
        - **Show Raycast at**: Center (or your preference)

        #### Appearance
        - **Theme**: Choose **Dark** (closest to Tokyo Night)
        - **Icon Style**: Your preference (SF Symbols recommended)

        #### Extensions to Enable
        These are built-in and should be enabled by default:
        - ✓ **File Search** - Search files across your Mac
        - ✓ **Applications** - Launch applications
        - ✓ **Window Management** - Manage open windows
        - ✓ **Clipboard History** - Access clipboard history
        - ✓ **Calculator** - Quick calculations
        - ✓ **System** - System commands (sleep, lock, etc.)

        #### Optional Useful Extensions (Install from Raycast Store)
        - **Homebrew** - Manage brew packages
        - **GitHub** - Search repos, issues, PRs
        - **Tailscale** - Control Tailscale connection
        - **Coffee** - Prevent Mac from sleeping
        - **Kill Process** - Easily kill hung processes

        ### 3. Configure Window Management Hotkeys (Optional)
        In Raycast Settings > Extensions > Window Management:
        - Set custom hotkeys for common window actions:
          - Left Half: **Ctrl+Opt+Left**
          - Right Half: **Ctrl+Opt+Right**
          - Maximize: **Ctrl+Opt+Return**
          - Center: **Ctrl+Opt+C**

        ## Verification
        - Press **Cmd+Space** - Raycast should open
        - Type to search files, apps, or run commands
        - All Tokyo Night styling is handled by SketchyBar
      '';
    };
  };
}
