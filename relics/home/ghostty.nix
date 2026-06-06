# Relic: Ghostty Terminal
# A GPU-accelerated terminal written in Rust and Zig, with a native GTK4 renderer
# on Linux. Distinct from Kitty by its native GTK integration and extended terminal
# protocol support. Both can coexist — each has its own configuration namespace.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.gui.ghostty;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "gui" "ghostty" "enable"] ["stc" "relics" "gui" "ghostty" "enable"])
  ];

  options.stc.relics.gui.ghostty = {
    enable = lib.mkEnableOption "Ghostty terminal emulator";
  };

  config = lib.mkIf cfg.enable {
    programs.ghostty.enable = true;
  };
}
