# Relic: AMD GPU
# Enables hardware graphics acceleration for AMD GPUs: VDPAU, VAAPI, 32-bit
# driver support (required by Steam and DXVK/Proton), and optional early KMS.
{ config, lib, pkgs, ... }:

let
  cfg = config.stc.relics.amdGpu;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "amdGpu" "enable" ] [ "stc" "relics" "amdGpu" "enable" ])
    (lib.mkRenamedOptionModule [ "stc" "amdGpu" "initrd" ] [ "stc" "relics" "amdGpu" "initrd" ])
  ];

  options.stc.relics.amdGpu = {
    enable = lib.mkEnableOption "AMD GPU support (VDPAU, VAAPI, 32-bit, optional early KMS)";

    initrd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Load the amdgpu kernel module in the initrd for early KMS framebuffer.
        Enables a graphical framebuffer during boot (Plymouth, LUKS prompt, etc.).
        Not required for normal desktop use — only enable if you need early display.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      # 32-bit driver support is required by Steam and DXVK/Proton.
      enable32Bit = true;
      extraPackages = with pkgs; [
        libvdpau
        libva-vdpau-driver
      ];
    };

    # Load amdgpu in initrd for KMS framebuffer at boot time.
    # Skipped by default — only useful when early display output is needed.
    boot.initrd.kernelModules = lib.mkIf cfg.initrd [ "amdgpu" ];
  };
}
