{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.cogitator.desktop;
in {
  imports = [
    # The removed kitty relic, kept imported so that a consumer still setting
    # its options gets its warning rather than "option does not exist" (#1).
    ../../relics/home/kitty.nix
    ../../relics/home/zen-browser.nix
    ../../relics/home/ghostty.nix
  ];

  options.stc.cogitator.desktop = {
    enable = lib.mkEnableOption "STC desktop GUI profile (ghostty, zen-browser, GIMP, VLC)";
  };

  config = lib.mkIf cfg.enable {
    # Both mkDefault: each relic is independent, this profile writes nothing
    # that assumes either of them, and at normal priority there was no way to
    # take the profile and decline a single program.
    stc.relics.gui.ghostty.enable = lib.mkDefault true;
    stc.relics.gui.zen-browser.enable = lib.mkDefault true;

    # Graphical pinentry for gpg-agent. Overrides the headless-safe default set
    # by cogitator-enginseer; inert if gpg-agent is not enabled.
    #
    # mkOverride 900, not mkForce, and the number is the whole point. This has
    # to beat enginseer's `mkDefault pinentry-curses` (priority 1000) when both
    # profiles are composed — that interaction is what provings/home-desktop.nix
    # checks. But mkForce (50) also beat the *consumer*: measured, someone
    # asking for pinentry-gnome3 with a plain definition got pinentry-qt anyway,
    # with no warning and no conflict. Silently ignoring a consumer is worse
    # than the conflicts issue #86 set out to remove. 900 sits between the two:
    # stronger than a default, weaker than a definition.
    services.gpg-agent.pinentry.package = lib.mkOverride 900 pkgs.pinentry-qt;

    home.packages = with pkgs; [
      gimp
      libnotify
      vlc
    ];
  };
}
