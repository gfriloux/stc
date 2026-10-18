{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.boot;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "boot" "enable"] ["stc" "relics" "boot" "enable"])
  ];

  options.stc.relics.boot = {
    enable = lib.mkEnableOption "systemd-boot + EFI bootloader configuration";
  };

  config = lib.mkIf cfg.enable {
    boot.loader = {
      # systemd-boot is what this relic sells; declining it means not using it.
      systemd-boot.enable = true;

      # mkDefault, not a bare true: setting this false is the standard remedy on
      # firmware that refuses EFI variable writes, and on a system installed
      # from a chroot where efivarfs is not mounted. The value stays the same
      # for every host that does not ask — the relic just stops being the reason
      # a consumer has to write mkForce to boot their hardware.
      efi.canTouchEfiVariables = lib.mkDefault true;
    };
  };
}
