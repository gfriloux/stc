# Relic: KDE Plasma 6
# Wayland-first Plasma 6 desktop: SDDM display manager, XDG portals, gvfs,
# tumbler (thumbnail service), and libinput. xserver is disabled — Plasma runs
# purely under Wayland. Keyboard layout and SDDM theme are configurable options.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.plasma6;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "plasma6" "enable"] ["stc" "relics" "plasma6" "enable"])
    (lib.mkRenamedOptionModule ["stc" "plasma6" "keyboardLayout"] ["stc" "relics" "plasma6" "keyboardLayout"])
    (lib.mkRenamedOptionModule ["stc" "plasma6" "sddmTheme"] ["stc" "relics" "plasma6" "sddmTheme"])
    (lib.mkRenamedOptionModule ["stc" "plasma6" "wayland"] ["stc" "relics" "plasma6" "wayland"])
  ];

  options.stc.relics.plasma6 = {
    enable = lib.mkEnableOption "KDE Plasma 6 desktop (SDDM + Wayland + XDG portal)";

    keyboardLayout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "xkb keyboard layout used by SDDM and Plasma (e.g. 'fr', 'de', 'us').";
    };

    sddmTheme = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        SDDM theme name. Empty string uses the SDDM built-in default.
        When using a custom theme (e.g. "catppuccin-mocha-mauve"), add the
        corresponding theme package to environment.systemPackages yourself —
        this relic does not install theme packages.
      '';
    };

    wayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use Wayland for the SDDM greeter. Set to false to fall back to X11 (older or incompatible GPUs).";
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      displayManager.sddm = {
        enable = true;
        wayland.enable = cfg.wayland;
        theme = cfg.sddmTheme;
      };

      desktopManager.plasma6.enable = true;

      # gvfs: virtual filesystem for Dolphin (MTP, SMB, trash, etc.)
      gvfs.enable = true;

      # tumbler: on-demand thumbnail generation for Dolphin and other KDE apps.
      tumbler.enable = true;

      # libinput: unified pointer/touchpad/touchscreen input handling.
      libinput.enable = true;

      xserver = {
        # Disable the X11 server — Plasma 6 runs under Wayland via SDDM.
        # xkb.layout is still read by libinput even without an X server.
        enable = false;
        xkb.layout = cfg.keyboardLayout;
      };
    };

    # XDG desktop portal — required by Flatpak, screen sharing, file pickers.
    # The GTK portal provides a fallback for non-KDE applications.
    xdg.portal = {
      enable = true;
      extraPortals = [];
      # Wildcard default lets each app pick the best available portal.
      config.common.default = "*";
    };

    # WirePlumber must be started as part of the graphical session.
    # Without this, audio may not initialise when Plasma launches.
    systemd.user.services.wireplumber.wantedBy = ["default.target"];
  };
}
