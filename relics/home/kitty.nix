# Relic: Kitty Terminal — removed (#1)
# Ghostty replaced it in cogitator-desktop, and the Nerd Fonts moved to
# stc.relics.gui.ghostty.fonts.enable. What is left is a tombstone: the options
# are still declared, so a consumer setting one gets a warning rather than
# "option does not exist", and they do nothing. Gone with the stc.* aliases at
# v1.0.0.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.gui.kitty;

  # nullOr, default null: an explicit `false` warns too — it was the documented
  # way to keep only ghostty, and it is dead code now.
  removedOption = lib.mkOption {
    type = lib.types.nullOr lib.types.bool;
    default = null;
    visible = false;
    description = "Removed (#1): has no effect.";
  };

  defined = lib.filter (name: lib.getAttrFromPath name cfg != null) [["enable"] ["fonts" "enable"]];
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "gui" "kitty" "enable"] ["stc" "relics" "gui" "kitty" "enable"])
    (lib.mkRenamedOptionModule ["stc" "gui" "kitty" "fonts" "enable"] ["stc" "relics" "gui" "kitty" "fonts" "enable"])
  ];

  options.stc.relics.gui.kitty = {
    enable = removedOption;
    fonts.enable = removedOption;
  };

  config.warnings =
    map (name: ''
      stc.relics.gui.kitty.${lib.concatStringsSep "." name} has no effect: the kitty relic was removed (#1).
      Use stc.relics.gui.ghostty instead; the Nerd Fonts now follow stc.relics.gui.ghostty.fonts.enable.
      Drop this definition: the option itself disappears at v1.0.0.
    '')
    defined;
}
