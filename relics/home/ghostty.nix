# Relic: Ghostty Terminal
# A GPU-accelerated terminal written in Zig, with a native GTK4 renderer on
# Linux. The fonts option installs a curated collection of Nerd Fonts —
# because a Techpriest reads glyphs others cannot perceive.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.gui.ghostty;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "gui" "ghostty" "enable"] ["stc" "relics" "gui" "ghostty" "enable"])
  ];

  options.stc.relics.gui.ghostty = {
    enable = lib.mkEnableOption "Ghostty terminal emulator";

    fonts.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install a curated set of Nerd Fonts alongside Ghostty.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ghostty.enable = true;

    home.packages = lib.mkIf cfg.fonts.enable (with pkgs; [
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
