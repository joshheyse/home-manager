{
  pkgs,
  lib,
  ...
}: let
  # Shared keyboard modifier key mappings
  capsLockToEscape = {
    HIDKeyboardModifierMappingSrc = 30064771129; # Caps Lock
    HIDKeyboardModifierMappingDst = 30064771113; # Escape
  };

  swapRightCommandControl = [
    {
      HIDKeyboardModifierMappingSrc = 30064771302; # Right Command
      HIDKeyboardModifierMappingDst = 30064771303; # Right Control
    }
    {
      HIDKeyboardModifierMappingSrc = 30064771303; # Right Control
      HIDKeyboardModifierMappingDst = 30064771302; # Right Command
    }
  ];

  swapLeftCommandOption = [
    {
      HIDKeyboardModifierMappingSrc = 30064771298; # Left Option
      HIDKeyboardModifierMappingDst = 30064771299; # Left Command
    }
    {
      HIDKeyboardModifierMappingSrc = 30064771299; # Left Command
      HIDKeyboardModifierMappingDst = 30064771298; # Left Option
    }
  ];

  basicMapping = [capsLockToEscape];
  fullSwapMapping = [capsLockToEscape] ++ swapRightCommandControl ++ swapLeftCommandOption;
in {
  # Shared nix-darwin module for all macOS machines

  system.primaryUser = lib.mkDefault "joshheyse";

  programs.zsh.enable = true;

  environment.systemPath = ["/opt/homebrew/bin"];

  environment.systemPackages = with pkgs; [
    zsh
    git
  ];

  nixpkgs.config.allowUnfree = true;

  # Yabai window manager (same config on all macs)
  services.yabai = {
    enable = true;
    config = {
      # Window borders
      window_border = "off";
      window_border_blur = "on";
      window_border_hidpi = "on";
      window_border_radius = 12;
      window_border_width = 4;

      # Window opacity
      window_opacity = "on";
      window_opacity_duration = "0.5";
      active_window_opacity = "1.0";
      normal_window_opacity = "0.5";

      # Padding and gaps
      top_padding = 6;
      bottom_padding = 6;
      left_padding = 6;
      right_padding = 6;
      window_gap = 6;

      # Layout
      layout = "bsp";

      # Mouse settings
      mouse_modifier = "fn";
      mouse_action1 = "move";
      mouse_action2 = "resize";
      mouse_follows_focus = "off";
      focus_follows_mouse = "off";

      # Split settings
      auto_balance = "off";
      split_ratio = "0.50";
      split_type = "auto";

      # Window placement
      window_placement = "second_child";
      window_topmost = "off";
      window_origin_display = "default";
      window_zoom_persist = "on";
    };
  };

  # Homebrew base configuration
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };

    # Base casks shared across all macs
    casks = [
      "betterdisplay"
      "bitwarden"
      "gimp"
      "kitty"
      "podman-desktop"
      "scroll-reverser"
      "sioyek"
      "utm"
      "xquartz"
    ];
  };

  # macOS system defaults
  system.defaults = {
    dock = {
      autohide = true;
      orientation = lib.mkDefault "bottom";
      show-recents = false;
      magnification = true;
      largesize = 40;
      tilesize = 37;
      minimize-to-application = true;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
      _FXShowPosixPathInTitle = false;
      FXEnableExtensionChangeWarning = false;
      FXDefaultSearchScope = "SCcf";
    };

    NSGlobalDomain = {
      # Appearance
      AppleInterfaceStyle = "Dark";
      _HIHideMenuBar = true;

      # Keyboard
      KeyRepeat = 1;
      InitialKeyRepeat = 15;
      ApplePressAndHoldEnabled = false;

      # Text input
      NSAutomaticCapitalizationEnabled = true;
      NSAutomaticPeriodSubstitutionEnabled = true;
      NSAutomaticSpellingCorrectionEnabled = false;

      # File extensions
      AppleShowAllExtensions = true;
    };

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
    };

    CustomUserPreferences = {
      "com.apple.loginwindow" = {
        TALLogoutSavesState = false;
        LoginwindowLaunchesRelaunchApps = false;
      };

      "com.apple.finder" = {
        ShowStatusBar = false;
        ShowTabView = false;
      };

      "NSGlobalDomain" = {
        AppleAccentColor = 4;
        AppleICUForce24HourTime = 1;
        AppleMiniaturizeOnDoubleClick = 0;
        AppleEnableSwipeNavigateWithScrolls = 0;
      };

      # XQuartz configuration
      "org.xquartz.X11" = {
        apps_menu = [
          ["Terminal" "xterm" "n"]
          ["Kitty" "kitty" "k"]
        ];
      };

      # Keyboard modifier key mappings
      ".GlobalPreferences" = {
        # Built-in MacBook keyboard
        "com.apple.keyboard.modifiermapping.0-0-0" = basicMapping;

        # Logitech keyboard
        "com.apple.keyboard.modifiermapping.1133-50490-0" = fullSwapMapping;

        # Keyboards with full modifier swaps
        "com.apple.keyboard.modifiermapping.6940-6957-0" = fullSwapMapping;
        "com.apple.keyboard.modifiermapping.9456-8266-0" = fullSwapMapping;
        "com.apple.keyboard.modifiermapping.9456-8353-0" = fullSwapMapping;

        # Keyboard with basic mapping only
        "com.apple.keyboard.modifiermapping.9456-8352-0" = fullSwapMapping;
      };
    };
  };
}
