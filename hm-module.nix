# hm-module.nix — Mullvad VPN GUI install + declarative ~/.config GUI prefs.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mullvad-vpn-gui;
in
{
  options.programs.mullvad-vpn-gui = {
    enable = lib.mkEnableOption "Mullvad VPN GUI client (Home Manager)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mullvad-vpn;
      defaultText = lib.literalExpression "pkgs.mullvad-vpn";
      description = "The mullvad-vpn package providing the GUI binary.";
    };

    settings = lib.mkOption {
      description = ''
        User-scope GUI preferences written to
        `$XDG_CONFIG_HOME/Mullvad VPN/gui_settings.json` on activation.
        These are GUI-only preferences (window state, tray icon style,
        notifications) — they do NOT change connection / privacy
        behavior. Daemon settings live under
        `services.mullvad-vpn-declarative.settings`.

        File is overwritten declaratively. To unmanage, set `enable = false`
        on this option; the file then remains as last-written.
      '';
      default = { };
      type = lib.types.submodule {
        options = {
          preferredLocale = lib.mkOption {
            type = lib.types.str;
            default = "system";
            description = "GUI language. 'system' follows the OS locale.";
          };
          autoConnect = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              GUI auto-connect (separate from daemon-level autoConnect).
              GUI-side: connects when the GUI window opens.
              Daemon-side: connects on daemon start.
              Usually you want the daemon-side one (more reliable).
            '';
          };
          enableSystemNotifications = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          monochromaticIcon = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Tray icon style. Monochrome blends with most themes.";
          };
          startMinimized = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Start hidden in tray instead of opening the main window.";
          };
          unpinnedWindow = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Allow window to be moved/resized freely (vs pinned to tray).";
          };
          animateMap = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Animate the connection-status map. Off saves CPU on weak hardware.";
          };
        };
      };
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Launch the GUI on session start (writes a .desktop entry to
        `$XDG_CONFIG_HOME/autostart/`). Independent of daemon auto-connect.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # GUI settings JSON — daemon ignores it; pure GUI-side.
    xdg.configFile."Mullvad VPN/gui_settings.json".text = builtins.toJSON {
      preferredLocale = cfg.settings.preferredLocale;
      autoConnect = cfg.settings.autoConnect;
      enableSystemNotifications = cfg.settings.enableSystemNotifications;
      monochromaticIcon = cfg.settings.monochromaticIcon;
      startMinimized = cfg.settings.startMinimized;
      unpinnedWindow = cfg.settings.unpinnedWindow;
      animateMap = cfg.settings.animateMap;
      browsedForSplitTunnelingApplications = [ ];
      changelogDisplayedForVersion = "";
      updateDismissedForVersion = "";
    };

    xdg.configFile."autostart/mullvad-vpn.desktop" = lib.mkIf cfg.autostart {
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Mullvad VPN
        Exec=${cfg.package}/bin/mullvad-gui
        Terminal=false
        X-GNOME-Autostart-enabled=true
      '';
    };
  };
}
