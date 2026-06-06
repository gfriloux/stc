# Cogitator: Plasma Desktop
# One enable option for a complete KDE Plasma 6 Wayland desktop:
# the Plasma 6 relic (SDDM + XDG portal + desktop services) composed with
# the Pipewire relic (RTKit + ALSA 32-bit + PulseAudio compat).
#
# Individual relic options remain tunable after activation:
#   stc.relics.plasma6.keyboardLayout, stc.relics.plasma6.sddmTheme
#   stc.relics.pipewire.enable (already true — override only to disable)
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.cogitator.plasma;
in {
  imports = [
    ../../relics/nixos/plasma6.nix
    ../../relics/nixos/pipewire.nix
  ];

  options.stc.cogitator.plasma = {
    enable = lib.mkEnableOption "STC Plasma 6 desktop profile (Plasma 6 + Pipewire)";
  };

  config = lib.mkIf cfg.enable {
    stc.relics.plasma6.enable = true;
    stc.relics.pipewire.enable = true;
  };
}
