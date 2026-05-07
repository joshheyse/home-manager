{config, ...}: let
  t = config.theme.tokyoNight;

  # Style shorthand: lnav wants color/background-color keys.
  fg = color: {inherit color;};
  fgBg = color: background: {
    inherit color;
    background-color = background;
  };
  fgBold = color: {
    inherit color;
    bold = true;
  };

  tokyoNightTheme = {
    vars = {
      black = t.bg;
      inherit (t) bg;
      inherit (t) bgDark;
      inherit (t) bgHighlight;
      inherit (t) fg;
      inherit (t) fgDark;
      inherit (t) comment;
      inherit (t) blue;
      inherit (t) cyan;
      inherit (t) green;
      inherit (t) red;
      inherit (t) yellow;
      inherit (t) orange;
      inherit (t) magenta;
      inherit (t) purple;
    };

    styles = {
      identifier = fg t.blue;
      text = fgBg t.fg t.bg;
      alt-text = fgBg t.fgDark t.bgDark;
      ok = fg t.green;
      error = fgBold t.red;
      warning = fgBold t.yellow;
      info = fg t.blue;
      hidden = fg t.comment;
      adjusted-time = fg t.magenta;
      skewed-time = fg t.orange;
      offset-time = fg t.cyan;
      invalid-msg = fg t.red;
      focused = fgBg t.fg t.bgHighlight;
      disabled-focused = fgBg t.comment t.bgHighlight;
      popup = fgBg t.fg t.bgDark;
      popup-border = fg t.blue;
      scrollbar = fgBg t.fg t.bgHighlight;
      h1 = fgBold t.magenta;
      h2 = fgBold t.blue;
      h3 = fgBold t.cyan;
      h4 = fg t.green;
      h5 = fg t.yellow;
      h6 = fg t.orange;
      hr = fg t.comment;
      hyperlink = {
        color = t.blue;
        underline = true;
      };
      list-glyph = fg t.blue;
      breadcrumb = fg t.comment;
      table-border = fg t.comment;
      table-header = fgBold t.blue;
      quote-border = fg t.comment;
      quoted-text = fg t.fgDark;
      footnote-border = fg t.comment;
      footnote-text = fg t.comment;
      snippet-border = fg t.comment;
      indent-guide = fg t.bgHighlight;
      selected-text = fgBg t.fg t.bgHighlight;
      fuzzy-match = fgBold t.yellow;
      cursor-line = fgBg t.fg t.bgHighlight;
      disabled-cursor-line = fgBg t.comment t.bgHighlight;
    };

    syntax-styles = {
      keyword = fg t.magenta;
      string = fg t.green;
      comment = {
        color = t.comment;
        italic = true;
      };
      doc-directive = fg t.blue;
      variable = fg t.cyan;
      symbol = fg t.cyan;
      re-special = fg t.orange;
      re-repeat = fg t.yellow;
      diff-delete = fg t.red;
      diff-add = fg t.green;
      diff-section = fg t.blue;
      file = fg t.blue;
      number = fg t.orange;
      null = fg t.orange;
      ascii-control = fg t.red;
      non-ascii = fg t.yellow;
      type = fg t.cyan;
      function = fg t.blue;
    };

    status-styles = {
      text = fgBg t.fgDark t.bgDark;
      warn = fgBg t.yellow t.bgDark;
      alert = fgBg t.red t.bgDark;
      active = fgBg t.green t.bgDark;
      inactive = fgBg t.comment t.bgDark;
      inactive-alert = fgBg t.red t.bgDark;
      title = {
        color = t.bg;
        background-color = t.blue;
        bold = true;
      };
      disabled-title = fgBg t.fgDark t.bgHighlight;
      subtitle = fgBg t.bg t.cyan;
      info = fgBg t.blue t.bgDark;
      hotkey = {
        color = t.yellow;
        background-color = t.bgDark;
        underline = true;
      };
      title-hotkey = {
        color = t.bg;
        background-color = t.blue;
        underline = true;
      };
      suggestion = fg t.comment;
    };

    log-level-styles = {
      trace = fg t.comment;
      debug = fg t.fgDark;
      info = {};
      stats = fg t.cyan;
      notice = fg t.green;
      warning = fg t.yellow;
      error = fg t.red;
      critical = fgBold t.red;
      fatal = {
        color = t.red;
        background-color = t.bgDark;
        bold = true;
      };
    };
  };
in {
  # lnav scans `<lnav-home>/configs/*/*.json` as read-only user config and
  # writes runtime `:config` changes to `<lnav-home>/config.json`. Placing our
  # Nix-managed settings under `configs/home-manager/` keeps them declarative
  # without colliding with lnav's own writable config file.
  xdg.configFile."lnav/configs/home-manager/theme.json".text = builtins.toJSON {
    "$schema" = "https://lnav.org/schemas/config-v1.schema.json";
    ui.theme-defs.tokyo-night = tokyoNightTheme;
  };

  xdg.configFile."lnav/configs/home-manager/ui.json".text = builtins.toJSON {
    "$schema" = "https://lnav.org/schemas/config-v1.schema.json";
    ui = {
      theme = "tokyo-night";
      mouse.mode = "enabled";
    };
  };
}
