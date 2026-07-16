# Cogitator: Workstation
# The hardened personal-workstation baseline, inspired by ANSSI/Sécurix "postes".
# Composes the DE-agnostic security socle — kernel + network + module-blacklist
# hardening plus YubiKey support — with a desktop environment selected by the
# `desktop` option. The DE stays orthogonal: adding i3 tomorrow is a new
# cogitator-i3 and an extra enum value, the socle does not change.
#
# Out of scope by design:
#   - SSH: no sshd is started. Enable stc.relics.hardening.ssh.enable yourself if
#     you want remote access.
#   - Gaming hardware (AMD GPU + Steam): that is cogitator-gaming, stacked
#     separately. This profile only handles the filesystem-exec side of gaming
#     (Proton needs exec in /tmp + /dev/shm) via hardening.filesystem.gaming.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.cogitator.workstation;
in {
  imports = [
    ./plasma.nix
    ../../relics/nixos/hardening/kernel.nix
    ../../relics/nixos/hardening/network.nix
    ../../relics/nixos/hardening/filesystem.nix
    ../../relics/nixos/hardening/modules.nix
    ../../relics/nixos/yubikey.nix
  ];

  options.stc.cogitator.workstation = {
    enable = lib.mkEnableOption "hardened workstation profile (desktop + hardening + YubiKey)";

    desktop = lib.mkOption {
      type = lib.types.enum ["plasma"];
      default = "plasma";
      description = ''
        Desktop environment for the workstation. A workstation always has a DE —
        a machine without one is a server, not a workstation. Currently only
        "plasma" (KDE Plasma 6). Extensible: adding "i3" means a new cogitator-i3
        and an extra value here.
      '';
    };

    yubikey = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable YubiKey system support (pcscd + udev rules). Set false on a workstation with no key.";
    };

    hardening.filesystem = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable filesystem hardening (/tmp noexec, /proc hidepid=2, /dev/shm
          restricted). Set false if hidepid=2 disturbs polkit / user D-Bus agents
          on your desktop and you have not wired them into the "proc" group.
        '';
      };

      gaming = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Relax filesystem hardening for Steam/Proton: drop noexec on /tmp and
          /dev/shm (kept nosuid/nodev, hidepid stays). Set true on a gaming
          workstation. Pair with cogitator-gaming for the GPU + Steam side.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    stc.cogitator.plasma.enable = cfg.desktop == "plasma";

    stc.relics.hardening.kernel.enable = true;
    stc.relics.hardening.network.enable = true;
    stc.relics.hardening.modules.enable = true;
    stc.relics.hardening.filesystem.enable = cfg.hardening.filesystem.enable;
    stc.relics.hardening.filesystem.gaming = cfg.hardening.filesystem.gaming;

    stc.relics.yubikey.enable = cfg.yubikey;
  };
}
