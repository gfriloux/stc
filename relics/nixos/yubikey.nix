# Relic: YubiKey system support
# Enables the PC/SC daemon (pcscd) for smart card communication and installs
# the YubiKey udev rules so the key is recognised without root privileges.
# Pair with the home relic (relics-yubikey-user) for the user-facing tools.
{ config, lib, pkgs, ... }:

let
  cfg = config.stc.yubikey;
in
{
  options.stc.yubikey = {
    enable = lib.mkEnableOption "YubiKey system support (pcscd + udev rules)";
  };

  config = lib.mkIf cfg.enable {
    # pcscd: PC/SC daemon required for smart card operations (PIV, OpenPGP slot).
    services.pcscd.enable = true;

    # udev rules so the YubiKey is accessible to the current user without sudo.
    services.udev.packages = [ pkgs.yubikey-personalization ];
  };
}
