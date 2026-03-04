{
  pkgs,
  lib,
  config,
  ...
}: let
  theme = config.theme.tokyoNight;
in {
  programs.starship = {
    enable = true;
    package = pkgs.starship;
    enableZshIntegration = true;
    settings = {
      format = lib.concatStrings [
        "[$os](bg:${theme.dark5} fg:${theme.bgDarkest})"
        "[$username](bg:${theme.dark5} fg:${theme.bgDarkest})[$hostname](bg:${theme.dark5} fg:${theme.bgDarkest})"
        "[](bg:${theme.blue} fg:${theme.dark5})"
        "$directory"
        "[](fg:${theme.blue} bg:${theme.fgGutter})"
        "$git_branch"
        "$git_state"
        "$git_status"
        "[](fg:${theme.fgGutter})"
        "$fill"
        "[](fg:${theme.bgDark})"
        "$status"
        "$cmd_duration"
        "$nix_shell"
        "$nodejs"
        "$conda"
        "$rust"
        "$golang"
        "$direnv"
        "$time"
        "$line_break"
        "$character"
      ];
      add_newline = false;
      command_timeout = 500;
      line_break = {
        disabled = false;
      };
      status = {
        disabled = false;
        format = "[$status ](bg:${theme.bgDark})";
      };
      cmd_duration = {
        min_time = 500;
        format = "[$duration ](bold yellow bg:${theme.bgDark})";
      };
      fill = {
        symbol = " ";
      };
      git_status = {
        ahead = "⇡$count";
        behind = "⇣$count";
        conflicted = "=$count";
        deleted = "✘$count";
        diverged = "⇕⇡$ahead_count⇣$behind_count";
        format = "[[($all_status $ahead_behind )](fg:${theme.blue} bg:${theme.fgGutter})]($style)";
        modified = "!$count";
        renamed = "»$count";
        staged = "+$count";
        stashed = "\\$$count";
        style = "bg:${theme.fgGutter}";
        untracked = "?$count";
      };
      directory = {
        read_only = " ";
        style = "fg:${theme.fg} bg:${theme.blue}";
        format = "[ $path ]($style)";
        truncation_length = 4;
        truncation_symbol = "…/";
        substitutions = {
          Documents = "󰈙 ";
          Downloads = " ";
          Music = " ";
          Pictures = " ";
        };
      };
      time = {
        disabled = false;
        time_format = "%R"; # Hour:Minute Format
        format = "[[ $time ](fg:${theme.fgDark} bg:${theme.bgDark})]($style)";
      };
      aws = {
        symbol = " ";
      };
      buf = {
        symbol = " ";
      };
      c = {
        symbol = " ";
      };
      conda = {
        symbol = " ";
        ignore_base = false;
        format = "[$symbol$environment](dimmed green) ";
      };
      dart = {
        symbol = " ";
      };
      direnv = {
        symbol = "󱁿 ";
        disabled = false;
        format = "[$symbol]($style)";
        loaded_msg = "";
        unloaded_msg = "";
        denied_msg = "";
        allowed_msg = "";
      };
      docker_context = {
        symbol = " ";
      };
      elixir = {
        symbol = " ";
      };
      elm = {
        symbol = " ";
      };
      git_branch = {
        symbol = " ";
        style = "bg:${theme.fgGutter}";
        format = "[[ $symbol $branch ](fg:${theme.blue} bg:${theme.fgGutter})]($style)";
      };
      golang = {
        symbol = " ";
        style = "bg:${theme.bgHighlight}";
        format = "[[ $symbol ($version) ](fg:${theme.blue} bg:${theme.bgHighlight})]($style)";
      };
      guix_shell = {
        symbol = " ";
      };
      haskell = {
        symbol = " ";
      };
      haxe = {
        symbol = "⌘ ";
      };
      hg_branch = {
        symbol = " ";
      };
      java = {
        symbol = " ";
      };
      julia = {
        symbol = " ";
      };
      lua = {
        symbol = " ";
      };
      memory_usage = {
        symbol = "󰍛 ";
      };
      meson = {
        symbol = "󰣖 ";
      };
      nim = {
        symbol = "󰆥 ";
      };
      nix_shell = {
        symbol = " ";
        format = "[$symbol$name ]($style)";
        pure_msg = "";
        impure_msg = "";
      };
      nodejs = {
        symbol = " ";
        style = "bg:${theme.bgHighlight}";
        format = "[[ $symbol ($version) ](fg:${theme.blue} bg:${theme.bgHighlight})]($style)";
      };
      hostname = {
        format = "@$hostname";
        disabled = false;
      };
      username = {
        format = "$user";
        disabled = false;
      };
      os = {
        disabled = false;
        format = "$symbol";
        symbols = {
          Alpine = " ";
          Amazon = " ";
          Android = " ";
          Arch = " ";
          CentOS = " ";
          Debian = " ";
          DragonFly = " ";
          Emscripten = " ";
          EndeavourOS = " ";
          Fedora = " ";
          FreeBSD = " ";
          Garuda = "﯑ ";
          Gentoo = " ";
          HardenedBSD = "ﲊ ";
          Illumos = " ";
          Linux = " ";
          Macos = " ";
          Manjaro = " ";
          Mariner = " ";
          MidnightBSD = " ";
          Mint = " ";
          NetBSD = " ";
          NixOS = " ";
          OpenBSD = " ";
          openSUSE = " ";
          OracleLinux = " ";
          Pop = " ";
          Raspbian = " ";
          Redhat = " ";
          RedHatEnterprise = " ";
          Redox = " ";
          Solus = "ﴱ ";
          SUSE = " ";
          Ubuntu = " ";
          Unknown = " ";
          Windows = "󰍲 ";
        };
      };
      package = {
        symbol = "󰏗 ";
      };
      python = {
        symbol = " ";
      };
      rlang = {
        symbol = "ﳒ ";
      };
      ruby = {
        symbol = " ";
      };
      rust = {
        symbol = " ";
        style = "bg:${theme.bgHighlight}";
        format = "[[ $symbol ($version) ](fg:${theme.blue} bg:${theme.bgHighlight})]($style)";
      };
      scala = {
        symbol = " ";
      };
      spack = {
        symbol = "🅢 ";
      };
    };
  };
}
