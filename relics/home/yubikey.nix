# Relic: YubiKey user tools (Home Manager)
# Installs the YubiKey management suite and runs yubikey-touch-detector as a
# user service. The detector fires a libnotify notification whenever the key
# waits for a physical touch (GPG signing, FIDO2 assertion, etc.).
# Requires the system relic (relics-yubikey-system) on the NixOS side.
{ config, lib, pkgs, ... }:

let
  cfg = config.stc.relics.yubikey;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "yubikey" "enable" ] [ "stc" "relics" "yubikey" "enable" ])
  ];

  options.stc.relics.yubikey = {
    enable = lib.mkEnableOption "YubiKey user tools (manager, touch detector, OATH app)";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      libfido2            # FIDO2/WebAuthn library and CLI tools
      yubikey-manager     # ykman — configure slots, FIDO2, PIV, OpenPGP
      yubikey-touch-detector # notifies when the key waits for a touch
      yubioath-flutter    # GUI for TOTP/HOTP (Yubico Authenticator)
    ];

    # Runs as a user service bound to the graphical session lifetime.
    # Sends a libnotify notification on touch-required operations.
    systemd.user.services.yubikey-touch-detector = {
      Unit = {
        Description = "YubiKey touch detector";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.yubikey-touch-detector}/bin/yubikey-touch-detector -libnotify";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
