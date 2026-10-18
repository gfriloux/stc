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
    # plasma6 stays at normal priority: this profile *is* Plasma 6, and with the
    # relic off it defines nothing at all. The conflict a consumer would hit is
    # the right answer — they want a different profile, not this one minus its
    # subject.
    stc.relics.plasma6.enable = true;

    # Pipewire is additive, so mkDefault. Measured: with the relic forced off the
    # configuration evaluates and the host is a coherent Plasma desktop without
    # STC's audio stack — which is an ordinary thing to want (JACK, bare ALSA, or
    # an interface owned by another service). At normal priority that needed
    # mkForce. This is the third case named in issue #86.
    stc.relics.pipewire.enable = lib.mkDefault true;
  };
}
