# Relic: Zen Browser
# A browser for Techpriests who value both performance and serenity.
# The Omnissiah approves of tabbed browsing.
{ config, lib, ... }:

let
  cfg = config.stc.gui.zen-browser;
in
{
  options.stc.gui.zen-browser = {
    enable = lib.mkEnableOption "Zen Browser";
  };

  config = lib.mkIf cfg.enable {
    programs.zen-browser.enable = true;
  };
}
