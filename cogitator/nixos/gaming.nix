# Cogitator: Gaming
# One enable option for a complete NixOS gaming setup on an AMD GPU machine:
# the AMD GPU relic (VDPAU, VAAPI, 32-bit drivers) composed with the Pipewire
# relic (RTKit + ALSA 32-bit + PulseAudio compat) and Steam enabled via the
# NixOS programs.steam option (proper wrappers, 32-bit libs, user namespaces).
#
# Hardening note: if cogitator-hardening or the hardening relics are active,
# you must set:
#   stc.hardening.kernel.gaming = true;
#   stc.hardening.filesystem.gaming = true;
# Steam requires user namespaces and exec access to /tmp and /dev/shm.
#
# Home Manager packages (Heroic, protonup-ng, emulators, etc.) are not managed
# here — add them to home.packages in your Home Manager configuration.
{ config, lib, ... }:

let
  cfg = config.stc.cogitator.gaming;
in
{
  imports = [
    ../../relics/nixos/amd-gpu.nix
    ../../relics/nixos/pipewire.nix
  ];

  options.stc.cogitator.gaming = {
    enable = lib.mkEnableOption "STC gaming profile (AMD GPU + Pipewire + Steam)";

    steam = {
      remotePlay = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open firewall ports for Steam Remote Play.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    stc.amdGpu.enable = true;
    stc.pipewire.enable = true;

    programs.steam = {
      enable = true;
      # Open firewall for Steam Remote Play if requested.
      remotePlay.openFirewall = cfg.steam.remotePlay;
    };
  };
}
