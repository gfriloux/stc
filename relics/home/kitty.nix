# Relic: Kitty Terminal
# A GPU-accelerated terminal. Fast, extensible, and worthy of an Enginseer.
# The fonts option installs a curated collection of Nerd Fonts —
# because a Techpriest reads glyphs others cannot perceive.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.gui.kitty;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "gui" "kitty" "enable"] ["stc" "relics" "gui" "kitty" "enable"])
    (lib.mkRenamedOptionModule ["stc" "gui" "kitty" "fonts" "enable"] ["stc" "relics" "gui" "kitty" "fonts" "enable"])
  ];

  options.stc.relics.gui.kitty = {
    enable = lib.mkEnableOption "Kitty terminal emulator";

    fonts.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install a curated set of Nerd Fonts alongside Kitty.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.kitty.enable = true;

    home.packages = lib.mkIf cfg.fonts.enable (with pkgs; [
      gtk_engines
      nerd-fonts.jetbrains-mono
      nerd-fonts.profont
      nerd-fonts.inconsolata
      nerd-fonts.iosevka
      nerd-fonts.bitstream-vera-sans-mono
      nerd-fonts.droid-sans-mono
      iosevka
    ]);
  };
}
