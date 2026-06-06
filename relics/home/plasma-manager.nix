# Relic: plasma-manager (Home Manager)
# Activates declarative KDE configuration via plasma-manager.
# Once enabled, the consumer configures their desktop entirely through
# programs.plasma.* options (theme, workspace, shortcuts, widgets, etc.)
# without touching ~/.config manually.
#
# The upstream plasma-manager module is injected via the inputs closure
# in relics/default.nix — consumers do not need to add plasma-manager
# as an input to their own flake.
{ config, lib, ... }:

let
  cfg = config.stc.relics.plasmaManager;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "plasmaManager" "enable" ] [ "stc" "relics" "plasmaManager" "enable" ])
  ];

  options.stc.relics.plasmaManager = {
    enable = lib.mkEnableOption "plasma-manager declarative KDE configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.plasma.enable = true;
  };
}
