{...}: {
  # Ghostty configuration
  # Note: Ghostty installed via Homebrew on macOS (marked as broken in nixpkgs)
  xdg.configFile."ghostty/config".source = ./config;
}
