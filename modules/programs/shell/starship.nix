{
  pkgs,
  lib,
  ...
}: {
  programs.starship = {
    enable = true;
    package = pkgs.starship;
    enableZshIntegration = true;
    settings = {
      format = lib.concatStrings [
        "[$os](bg:#a3aed2 fg:#090c0c)"
        "[$username](bg:#a3aed2 fg:#090c0c)[$hostname](bg:#a3aed2 fg:#090c0c)"
        "[](bg:#769ff0 fg:#a3aed2)"
        "$directory"
        "[](fg:#769ff0 bg:#394260)"
        "$git_branch"
        "$git_state"
        "$git_status"
        "[](fg:#394260)"
        "$fill"
        "[](fg:#1d2230)"
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
      command_timeout = 1000;
      line_break = {
        disabled = false;
      };
      status = {
        disabled = false;
        format = "[$status ](bg:#1d2230)";
      };
      cmd_duration = {
        min_time = 500;
        format = "[$duration ](bold yellow bg:#1d2230)";
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
        format = "[[($all_status $ahead_behind )](fg:#769ff0 bg:#394260)]($style)";
        modified = "!$count";
        renamed = "»$count";
        staged = "+$count";
        stashed = "\\$$count";
        style = "bg:#394260";
        untracked = "?$count";
      };
      directory = {
        read_only = " ";
        style = "fg:#e3e5e5 bg:#769ff0";
        format = "[ $path ]($style)";
        truncation_length = 4;
        truncation_symbol = "…/";
        substitutions = {
          Documents = "󰈙 ";
          Downloads = " ";
          Music = " ";
          Pictures = " ";
        };
      };
      time = {
        disabled = false;
        time_format = "%R"; # Hour:Minute Format
        format = "[[ $time ](fg:#a0a9cb bg:#1d2230)]($style)";
      };
      aws = {
        symbol = " ";
      };
      buf = {
        symbol = " ";
      };
      c = {
        symbol = " ";
      };
      conda = {
        symbol = " ";
        ignore_base = false;
        format = "[$symbol$environment](dimmed green) ";
      };
      dart = {
        symbol = " ";
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
        symbol = " ";
      };
      elixir = {
        symbol = " ";
      };
      elm = {
        symbol = " ";
      };
      git_branch = {
        symbol = " ";
        style = "bg:#394260";
        format = "[[ $symbol $branch ](fg:#769ff0 bg:#394260)]($style)";
      };
      golang = {
        symbol = " ";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };
      guix_shell = {
        symbol = " ";
      };
      haskell = {
        symbol = " ";
      };
      haxe = {
        symbol = "⌘ ";
      };
      hg_branch = {
        symbol = " ";
      };
      java = {
        symbol = " ";
      };
      julia = {
        symbol = " ";
      };
      lua = {
        symbol = " ";
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
        symbol = " ";
        format = "[$symbol$name ]($style)";
        pure_msg = "";
        impure_msg = "";
      };
      nodejs = {
        symbol = " ";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
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
          Alpine = " ";
          Amazon = " ";
          Android = " ";
          Arch = " ";
          CentOS = " ";
          Debian = " ";
          DragonFly = " ";
          Emscripten = " ";
          EndeavourOS = " ";
          Fedora = " ";
          FreeBSD = " ";
          Garuda = "﯑ ";
          Gentoo = " ";
          HardenedBSD = "ﲊ ";
          Illumos = " ";
          Linux = " ";
          Macos = " ";
          Manjaro = " ";
          Mariner = " ";
          MidnightBSD = " ";
          Mint = " ";
          NetBSD = " ";
          NixOS = " ";
          OpenBSD = " ";
          openSUSE = " ";
          OracleLinux = " ";
          Pop = " ";
          Raspbian = " ";
          Redhat = " ";
          RedHatEnterprise = " ";
          Redox = " ";
          Solus = "ﴱ ";
          SUSE = " ";
          Ubuntu = " ";
          Unknown = " ";
          Windows = "󰍲 ";
        };
      };
      package = {
        symbol = "󰏗 ";
      };
      python = {
        symbol = " ";
      };
      rlang = {
        symbol = "ﳒ ";
      };
      ruby = {
        symbol = " ";
      };
      rust = {
        symbol = " ";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };
      scala = {
        symbol = " ";
      };
      spack = {
        symbol = "🅢 ";
      };
    };
  };
}
