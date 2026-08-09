{
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isLinux;
in {
  config = lib.mkIf isLinux {
    dconf.settings = {
      "org/gnome/evolution/shell" = {
        # Keep the application switcher, but reclaim the space used by its
        # Mail, Contacts, Calendar, Tasks, and Memos labels.
        buttons-style = "icons";
      };

      "org/gnome/evolution/mail" = {
        # A narrow message list works better beside the preview than above it.
        layout = 1;
        global-view-setting = true;

        # The calendar/tasks summary consumes a full column in the mail view.
        show-to-do-bar = false;
        show-to-do-bar-sub = false;
      };
    };

    # Evolution stores the selected message-list view outside GSettings. Its
    # built-in wide view uses a compact two-line Subject / Sender + Date row.
    # This marker contains no account data; accounts remain owned by GOA.
    xdg.configFile."evolution/mail/views/current_view-global_view_setting.xml" = {
      force = true;
      text = ''
        <?xml version="1.0"?>
        <GalViewCurrentView current_view="Wide_View_Normal" current_view_type="etable"/>
      '';
    };
  };
}
