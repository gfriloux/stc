---
title: Server Survivability
description: A headless host reboots itself instead of waiting for a console nobody is at.
---

**Module:** `stc.nixosModules.relics-server-survivability`

Stock NixOS defaults are tuned for a machine with someone in front of it. On a
remote host, each of the defaults below turns a recoverable fault into a dead
machine:

| Stock default | What happens on a headless host | What the relic does |
|---|---|---|
| Emergency mode on | A bad mount or fsck drops the boot into a root shell nobody can reach, and sshd never starts | Skips emergency mode; the boot carries on and you can log in to investigate |
| No watchdog | A hung kernel or PID 1 waits for a provider console, IPMI or a hands-on reboot | Arms the hardware watchdog (30 s) |
| `kernel.panic = 0` | A panicked kernel sits there forever | `panic=30` on the kernel command line |
| GRUB keeps 100 generations, systemd-boot all of them | Generations fill a small ESP until the bootloader install fails, so the host still boots but can no longer be updated | Keeps 5 generations at boot |
| Suspend allowed | A stray `systemctl suspend` takes the host offline, with nothing to wake it | Refuses suspend and hibernation |

Enabled by default (`lib.mkDefault`) by the four server profiles:
[docker-server](/stc/en/cogitator/docker-server/),
[dreadnought](/stc/en/cogitator/dreadnought/),
[sarcophagus-aws](/stc/en/cogitator/sarcophagus-aws/) and
[sarcophagus-kvm](/stc/en/cogitator/sarcophagus-kvm/).

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.serverSurvivability.enable` | bool | `false` | Enable the relic |
| `stc.relics.serverSurvivability.disableEmergencyMode` | bool | `true` | No stage 2 emergency shell (`systemd.enableEmergencyMode = mkDefault false`) |
| `stc.relics.serverSurvivability.panicReboot` | bool | `true` | `panic=30` and `boot.panic_on_fail` on the kernel command line |
| `stc.relics.serverSurvivability.watchdog.enable` | bool | `true` | Arm the hardware watchdog |
| `stc.relics.serverSurvivability.watchdog.runtimeSec` | string | `"30s"` | `RuntimeWatchdogSec` |
| `stc.relics.serverSurvivability.bootGenerations` | null or positive int | `5` | `configurationLimit` for GRUB and systemd-boot (as a default); `null` leaves the bootloader's own |
| `stc.relics.serverSurvivability.forbidSleep` | bool | `true` | `AllowSuspend=no`, `AllowHibernation=no` |

Each behaviour has its own switch. For example, to keep the emergency shell on a
host you can reach over IPMI:

```nix
stc.relics.serverSurvivability.disableEmergencyMode = false;
```

## The watchdog needs a device

`RuntimeWatchdogSec` only protects you if there is a watchdog device. Bare
metal generally has one. A VM has one only if the hypervisor exposes it: QEMU's
q35 machine provides `iTCO_wdt`, but other hypervisors may not. **Without a
device, systemd logs it and carries on.** That is harmless, but it does not
protect anything. Check on the host:

```bash
journalctl -b -o cat _PID=1 | grep -i watchdog
# Watchdog running with a hardware timeout of 30s.   ← armed
```

If a slow firmware watchdog resets the machine spuriously, raise
`watchdog.runtimeSec`. `RebootWatchdogSec` is not set because systemd already
defaults it to 10 min.

## Panic, and the hardening relic

The [kernel hardening relic](/stc/en/relics/hardening/) sets the
`kernel.panic` sysctl to `30`. This relic puts the same value on the command
line, so it covers the window before `systemd-sysctl` runs (the initrd
included). Because the values match, the timeout does not change mid-boot. The
relic never writes the sysctl itself.

A cloud image module from nixpkgs (`amazon-image.nix`, the Azure, GCE and
DigitalOcean configs) adds `panic=1` of its own. Stacked with this relic, both
values end up on the command line and the kernel keeps the last one, which
depends on module merge order. Check `/proc/cmdline` on such a host.

## Panic reboot and impermanence's emergency stop

`disableEmergencyMode` only affects stage 2. The initrd keeps its own emergency
target, but `panicReboot` also sets `boot.panic_on_fail`, which makes the initrd
crash the kernel as soon as that target starts. So
[`stc.relics.impermanence.onRollbackFailure = "emergency"`](/stc/en/relics/impermanence/)
would no longer stop and wait for a human. With `panic=30`, it would reboot every
30 s for as long as the rollback keeps failing.

The relic **refuses to build** with that combination, and the message tells you
to pick one:

```nix
# Keep the stop, give up the automatic reboot on initrd failure:
stc.relics.serverSurvivability.panicReboot = false;
# …or keep the reboot, and let a failed rollback boot on, marked degraded:
stc.relics.impermanence.onRollbackFailure = "continue";
```

## Why not nixpkgs' `profiles/headless.nix`

The upstream profile covers emergency mode and panic, but it also does two
things that do not belong here:

- It **disables `serial-getty@ttyS0`**. On a VPS, the provider's serial console
  is often the only out-of-band access.
- It adds `nomodeset vga=0x317`, which are display decisions.

The relic picks its settings one by one instead of importing the profile.

## Proving

`provings/docker-server.nix` boots the profile and runs every check twice: on a
node with the relic, then on one with the relic off. The checks are the missing
`emergency.service`, `panic=30` in `/proc/cmdline`, systemd's own "Watchdog
running … 30s" log line, and `AllowSuspend=no`. Each check must pass on the
first node and fail on the second.

## See Also

- [Overridable defaults](/stc/en/reference/overridable-defaults/)
- [Impermanence](/stc/en/relics/impermanence/) — `onRollbackFailure`
