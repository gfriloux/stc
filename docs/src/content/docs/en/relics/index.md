---
title: Relics
description: Overview of STC atomic modules — one concern per relic, all under the stc.* namespace.
sidebar:
  order: 0
---

A relic is an atomic NixOS or Home Manager module with a single responsibility.
Each relic is self-contained: it declares its options, applies its configuration,
and does nothing else. Nothing is enabled by default.

## The stc.* Namespace

All relic options live under `stc.*`. Each relic has its own sub-namespace:

```nix
stc.relics.boot.enable = true;
stc.relics.zfs.enable = true;
stc.relics.networking.enable = true;
stc.relics.hardening.kernel.enable = true;
stc.relics.docker.traefik.enable = true;
stc.relics.gui.kitty.enable = true;
```

This namespace is isolated from NixOS and Home Manager options. No collisions.

## How to Use a Relic

1. Import the module into your `nixosSystem` or `homeManagerConfiguration`
2. Set `enable = true` in your configuration

```nix
# flake.nix
modules = [
  stc.nixosModules.relics-boot
  stc.nixosModules.relics-zfs
];

# configuration.nix
{
  stc.relics.boot.enable = true;
  stc.relics.zfs.enable = true;
  stc.relics.zfs.scrubInterval = "weekly";
}
```

## NixOS Relics

| Module name | Enable option | Purpose |
|-------------|---------------|---------|
| `relics-boot` | `stc.relics.boot.enable` | systemd-boot + EFI (bootloader only) |
| `relics-zfs` | `stc.relics.zfs.enable` | ZFS-compatible kernel, auto-scrub, TRIM, ZED |
| `relics-networking` | `stc.relics.networking.enable` | DHCP, Quad9 DNS, search domain |
| `relics-impermanence` | `stc.relics.impermanence.enable` | ZFS rollback at boot, persistent paths |
| `relics-aws` | `stc.relics.aws.enable` | EC2 drivers, AWS NTP, serial console, EBS extension |
| `relics-vm-variant` | `stc.relics.vmVariant.enable` | Boot this host as a local VM, secrets/images/pools neutralised (VM build only) |
| `relics-pre-switch-checks` | `stc.relics.preSwitchChecks.enable` | Abort a switch that would activate another host's closure; print the diff on a remote deploy |
| `relics-server-survivability` | `stc.relics.serverSurvivability.enable` | Headless host: no emergency shell, reboot on panic, hardware watchdog, bounded `/boot`, no suspend |
| `relics-nix-housekeeping` | `stc.relics.nixHousekeeping.enable` | Long-lived host: scheduled GC, GC under disk pressure, weekly dedup, builds that yield, journal cap |
| `relics-state` | `stc.relics.state.paths` (no `enable`) | Manifest of the persistent state the enabled relics create — descriptive only |
| `relics-smart` | `stc.relics.smart.enable` | smartd over every SMART disk, alerts handed to your own `notifyCommand` — physical disks only |
| `relics-polkit-units` | `stc.relics.polkitUnits.enable` | Let a group start, stop or restart named units without sudo — one generated, scoped polkit rule |
| `relics-heartbeat` | `stc.relics.heartbeat.enable` | Named jobs ping your monitor on each success, and only then — a job that stops running raises an alert |
| `relics-amd-gpu` | `stc.relics.amdGpu.enable` | AMD GPU: VDPAU, VAAPI, 32-bit drivers, optional early KMS |
| `relics-pipewire` | `stc.relics.pipewire.enable` | Pipewire: RTKit + ALSA 32-bit + PulseAudio compat |
| `relics-plasma6` | `stc.relics.plasma6.enable` | KDE Plasma 6 Wayland desktop (SDDM + XDG portal) |
| `relics-yubikey-system` | `stc.relics.yubikey.enable` | YubiKey system layer: pcscd + udev rules |
| `relics-traefik` | `stc.relics.traefik.enable` | Native NixOS Traefik reverse proxy + Let's Encrypt |
| `relics-vaultwarden` | `stc.relics.vaultwarden.enable` | Vaultwarden server (Bitwarden-compatible) |
| `relics-hardening-kernel` | `stc.relics.hardening.kernel.enable` | Kernel sysctl (ASLR, kptr_restrict, dmesg, etc.) |
| `relics-hardening-network` | `stc.relics.hardening.network.enable` | Network sysctl (anti-spoofing, SYN cookies, ICMP) |
| `relics-hardening-filesystem` | `stc.relics.hardening.filesystem.enable` | /tmp noexec, /proc hidepid, /dev/shm restricted |
| `relics-hardening-ssh` | `stc.relics.hardening.ssh.enable` | Hardened OpenSSH, key-only auth |
| `relics-hardening-modules` | `stc.relics.hardening.modules.enable` | Blacklist high-risk / unused kernel modules (FireWire DMA, rare net protocols) |
| `relics-hardening-scheduler` | `stc.relics.hardening.scheduler.enable` | cron/at restricted to an explicit allowlist (inert unless a scheduler runs) |
| `relics-docker-traefik` | `stc.relics.docker.traefik.enable` | Traefik v3 reverse proxy container (Docker) |
| `relics-docker-socket-proxy` | `stc.relics.docker.socketProxy.enable` | Filtering proxy in front of the Docker socket |
| `relics-docker-crowdsec` | `stc.relics.docker.crowdsec.enable` | CrowdSec IDS/IPS container |
| `relics-docker-guards` | `stc.relics.docker.guards.enable` | Warn about containers published on every interface or mounting the raw Docker socket |
| `relics-docker-notify` | `stc.relics.docker.notify.enable` | Container failure notifications (transport-agnostic) |

## Home Manager Relics

| Module name | Enable option | Purpose |
|-------------|---------------|---------|
| `relics-kitty` | `stc.relics.gui.kitty.enable` | Kitty terminal + Nerd Fonts |
| `relics-ghostty` | `stc.relics.gui.ghostty.enable` | Ghostty terminal (GPU-accelerated, native GTK4) |
| `relics-zen-browser` | `stc.relics.gui.zen-browser.enable` | Zen Browser |
| `relics-yubikey-user` | `stc.relics.yubikey.enable` | YubiKey user tools: ykman, touch detector, OATH app |
| `relics-plasma-manager` | `stc.relics.plasmaManager.enable` | Declarative KDE configuration via plasma-manager |

## See Also

- [Cogitator profiles](/stc/en/cogitator/) — composed relics for common use cases
- [Hardening relics](/stc/en/relics/hardening/) — all six hardening modules in detail
- [AMD GPU](/stc/en/relics/amd-gpu/) — GPU relic with gaming compatibility
- [Pipewire](/stc/en/relics/pipewire/) — audio relic
- [Plasma 6](/stc/en/relics/plasma6/) — KDE Plasma 6 desktop relic
- [YubiKey](/stc/en/relics/yubikey/) — two-relic YubiKey setup
- [Plasma Manager](/stc/en/relics/plasma-manager/) — declarative KDE configuration
- [Docker relics](/stc/en/relics/docker/) — Traefik, socket-proxy, CrowdSec, and notify
- [AWS](/stc/en/relics/aws/) — EC2 drivers and AWS configuration
- [Traefik](/stc/en/relics/traefik/) — native NixOS reverse proxy
- [Vaultwarden](/stc/en/relics/vaultwarden/) — Bitwarden-compatible server
- [VM Variant](/stc/en/relics/vm-variant/) — boot your own host in a local VM before deploying
- [Pre-Switch Checks](/stc/en/relics/pre-switch-checks/) — refuse to activate the wrong host's closure
- [Server Survivability](/stc/en/relics/server-survivability/) — reboot instead of waiting for a console
- [Nix Housekeeping](/stc/en/relics/nix-housekeeping/) — a bounded store and journal
- [SMART](/stc/en/relics/smart/) — disk failure warnings before the pool degrades
- [polkit unit delegation](/stc/en/relics/polkit-units/) — `systemctl restart` on named units, without sudo
- [Heartbeat](/stc/en/relics/heartbeat/) — be told when a scheduled job stops succeeding
- [State manifest](/stc/en/reference/state-manifest/) — what to back up, as the relics declare it
