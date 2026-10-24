# Relic: Server Survivability
#
# A headless machine has no one at the console. Every stock default below is
# tuned for a machine someone can sit in front of, and on a remote host each one
# turns a recoverable fault into a dead machine:
#
#   - emergency mode: a bad mount or fsck drops stage 2 into a root shell that
#     nobody can reach, with sshd not started — indistinguishable from an outage;
#   - no watchdog: a hung kernel or PID 1 waits for out-of-band intervention;
#   - kernel.panic = 0: a panicked kernel sits there forever;
#   - a loose /boot: GRUB keeps 100 generations, systemd-boot all of them; on a
#     small ESP the bootloader install fails first, and the host can still boot
#     but no longer be updated;
#   - suspend allowed: a stray `systemctl suspend` or a misrouted ACPI event
#     takes the host offline with nothing to wake it.
#
# WHY NOT IMPORT nixos/modules/profiles/headless.nix. It covers emergency mode
# and panic, but it also disables serial-getty@ttyS0 — on a VPS the provider's
# serial console is the *only* out-of-band access — and adds `nomodeset
# vga=0x317`, display decisions with no place in a survivability relic. Do not
# "simplify" this module into that import.
#
# Panic: the cmdline carries panic=30, the same value relics/nixos/hardening/
# kernel.nix writes as the kernel.panic sysctl. The cmdline covers the window
# before systemd-sysctl runs (initrd included); matching the value means the
# timeout does not change mid-boot. This relic never writes the sysctl itself:
# both relics writing it at normal priority would be a conflict.
#
# Panic and impermanence DO collide, and the relic refuses the combination.
# systemd.enableEmergencyMode only removes stage 2's emergency units — the
# initrd keeps its emergency.target. But boot.panic_on_fail makes the initrd's
# panic-on-fail.service (wantedBy emergency.target) crash the kernel, so
# stc.relics.impermanence.onRollbackFailure = "emergency" would no longer stop
# and wait for a human: with panic=30 it would reboot every 30 s for as long as
# the rollback fails. Both are availability/integrity choices; the consumer
# makes it explicitly, by assertion, rather than one silently winning.
#
# Every setting a consumer may reasonably want otherwise is written with
# mkDefault, so it can be overridden without mkForce. The cmdline is a list and
# merges; it needs no priority.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.serverSurvivability;

  # The impermanence relic may not be imported at all; read its option only if
  # it exists.
  rollbackFailure =
    lib.attrByPath ["stc" "relics" "impermanence" "onRollbackFailure"] "continue" config;
in {
  options.stc.relics.serverSurvivability = {
    enable = lib.mkEnableOption ''
      defaults for a headless host that must recover without anyone at the console
    '';

    disableEmergencyMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Do not drop stage 2 into an emergency shell when a unit it needs fails
        (typically a mount or an fsck). The boot carries on instead, so sshd
        starts and the failure can be investigated remotely.

        The initrd is not affected: it keeps its own emergency target. See
        `panicReboot` for how that target behaves on a server.
      '';
    };

    panicReboot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Reboot 30 seconds after a kernel panic (`panic=30` on the kernel command
        line) instead of waiting forever, and panic rather than drop to a shell
        when stage 1 fails (`boot.panic_on_fail`).

        30 seconds is the value the hardening relic writes as the
        `kernel.panic` sysctl, so the timeout is the same before and after
        `systemd-sysctl` runs.

        `boot.panic_on_fail` crashes the kernel whenever the initrd reaches its
        emergency target. That contradicts
        `stc.relics.impermanence.onRollbackFailure = "emergency"`, which wants a
        failed rollback to stop and wait for a human; the two together would
        reboot in a loop. The combination is refused by assertion: set this to
        `false` to keep the stop, or set `onRollbackFailure` to `"continue"`.
      '';
    };

    watchdog = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Have systemd arm the hardware watchdog, so a hung kernel or PID 1
          reboots the machine.

          This needs a watchdog device. Bare metal generally has one; a VM has
          one only if the hypervisor exposes it (QEMU's q35 machine exposes
          `iTCO_wdt`). Without a device systemd logs it and carries on: the
          setting is harmless, but it protects nothing. Check with
          `journalctl -b | grep -i watchdog`.
        '';
      };

      runtimeSec = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        example = "1min";
        description = ''
          `RuntimeWatchdogSec`: the hardware timeout. systemd pings the device
          at half this interval; if PID 1 stops pinging, the device resets the
          machine. Raise it if a slow firmware watchdog trips spuriously.
        '';
      };
    };

    bootGenerations = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 5;
      description = ''
        How many generations the bootloader keeps (`configurationLimit`, set on
        both GRUB and systemd-boot as a default). Bounds `/boot`, so a small ESP
        does not fill and make the next deploy fail at bootloader install. Older
        generations stay in the Nix store until garbage-collected; they just are
        no longer offered at boot. `null` leaves the bootloader's own default.
      '';
    };

    forbidSleep = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Refuse suspend and hibernation (`AllowSuspend=no`,
        `AllowHibernation=no`). A suspended server has nothing to wake it.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.panicReboot && rollbackFailure == "emergency");
          message = ''
            stc.relics.serverSurvivability.panicReboot and
            stc.relics.impermanence.onRollbackFailure = "emergency" contradict
            each other. panicReboot puts boot.panic_on_fail on the kernel command
            line, which crashes the kernel as soon as the initrd reaches its
            emergency target, so a failed rollback would not stop and wait for a
            human: it would reboot every 30 s for as long as the rollback fails.

            Pick one:
              - keep the stop:   stc.relics.serverSurvivability.panicReboot = false;
              - let the boot go on (the impermanence default, which marks the
                system degraded): stc.relics.impermanence.onRollbackFailure = "continue";
          '';
        }
      ];
    }

    (lib.mkIf cfg.disableEmergencyMode {
      # mkDefault: a consumer with console access (IPMI, a KVM over IP) may
      # prefer the shell, and should not need mkForce to say so.
      systemd.enableEmergencyMode = lib.mkDefault false;
    })

    (lib.mkIf cfg.panicReboot {
      boot.kernelParams = ["panic=30" "boot.panic_on_fail"];
    })

    # RebootWatchdogSec is deliberately absent: systemd already defaults it to
    # 10min (measured on a bare node). KExecWatchdogSec too: STC's hardening
    # disables kexec, and no profile kexecs.
    (lib.mkIf cfg.watchdog.enable {
      systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault cfg.watchdog.runtimeSec;
    })

    (lib.mkIf (cfg.bootGenerations != null) {
      boot.loader.grub.configurationLimit = lib.mkDefault cfg.bootGenerations;
      boot.loader.systemd-boot.configurationLimit = lib.mkDefault cfg.bootGenerations;
    })

    (lib.mkIf cfg.forbidSleep {
      systemd.sleep.settings.Sleep = {
        AllowSuspend = lib.mkDefault "no";
        AllowHibernation = lib.mkDefault "no";
      };
    })
  ]);
}
