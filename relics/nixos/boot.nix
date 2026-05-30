{ config, lib, ... }:

let
  cfg = config.stc.boot;
in
{
  options.stc.boot = {
    enable = lib.mkEnableOption "systemd-boot + EFI bootloader configuration";
  };

  config = lib.mkIf cfg.enable {
    boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };
}
