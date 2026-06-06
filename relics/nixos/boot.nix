{ config, lib, ... }:

let
  cfg = config.stc.relics.boot;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "boot" "enable" ] [ "stc" "relics" "boot" "enable" ])
  ];

  options.stc.relics.boot = {
    enable = lib.mkEnableOption "systemd-boot + EFI bootloader configuration";
  };

  config = lib.mkIf cfg.enable {
    boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };
}
