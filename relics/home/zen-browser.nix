# Relic: Zen Browser
# A browser for Techpriests who value both performance and serenity.
# The Omnissiah approves of tabbed browsing.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.gui.zen-browser;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "gui" "zen-browser" "enable"] ["stc" "relics" "gui" "zen-browser" "enable"])
  ];

  options.stc.relics.gui.zen-browser = {
    enable = lib.mkEnableOption "Zen Browser";
  };

  config = lib.mkIf cfg.enable {
    programs.zen-browser.enable = true;
  };
}
