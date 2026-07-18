{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.cogitator.desktop;
in {
  imports = [
    ../../relics/home/kitty.nix
    ../../relics/home/zen-browser.nix
    ../../relics/home/ghostty.nix
  ];

  options.stc.cogitator.desktop = {
    enable = lib.mkEnableOption "STC desktop GUI profile (kitty, ghostty, zen-browser, GIMP, VLC)";
  };

  config = lib.mkIf cfg.enable {
    stc.relics.gui.kitty.enable = true;
    stc.relics.gui.ghostty.enable = true;
    stc.relics.gui.zen-browser.enable = true;

    # Graphical pinentry for gpg-agent. Overrides the headless-safe default set
    # by cogitator-enginseer; inert if gpg-agent is not enabled.
    services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-qt;

    home.packages = with pkgs; [
      gimp
      libnotify
      vlc
    ];
  };
}
