# Relic: Pipewire
# Modern audio server replacing PulseAudio. RTKit gives Pipewire real-time
# scheduling priority. ALSA 32-bit support is required by Steam and Wine.
# PulseAudio compat keeps legacy applications working without changes.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.pipewire;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "pipewire" "enable"] ["stc" "relics" "pipewire" "enable"])
  ];

  options.stc.relics.pipewire = {
    enable = lib.mkEnableOption "Pipewire audio server (RTKit + ALSA 32-bit + PulseAudio compat)";
  };

  config = lib.mkIf cfg.enable {
    # RTKit grants Pipewire real-time scheduling priority on demand.
    security.rtkit.enable = true;

    # Disable PulseAudio — Pipewire's pulse compat replaces it.
    services.pulseaudio.enable = false;

    services.pipewire = {
      enable = true;

      alsa = {
        enable = true;
        # 32-bit ALSA support is required by Steam and 32-bit Wine applications.
        support32Bit = true;
      };

      # PulseAudio compatibility layer — transparent for legacy applications.
      pulse.enable = true;
    };
  };
}
