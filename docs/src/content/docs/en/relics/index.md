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
stc.boot.enable = true;
stc.zfs.enable = true;
stc.networking.enable = true;
stc.hardening.kernel.enable = true;
stc.docker.traefik.enable = true;
stc.gui.kitty.enable = true;
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
  stc.boot.enable = true;
  stc.zfs.enable = true;
  stc.zfs.scrubInterval = "weekly";
}
```

## NixOS Relics

| Module name | Enable option | Purpose |
|-------------|---------------|---------|
| `relics-boot` | `stc.boot.enable` | systemd-boot + EFI (bootloader only) |
| `relics-zfs` | `stc.zfs.enable` | ZFS-compatible kernel, auto-scrub, TRIM, ZED |
| `relics-networking` | `stc.networking.enable` | DHCP, Quad9 DNS, search domain |
| `relics-impermanence` | `stc.impermanence.enable` | ZFS rollback at boot, persistent paths |
| `relics-aws` | `stc.aws.enable` | EC2 drivers, AWS NTP, serial console, EBS extension |
| `relics-amd-gpu` | `stc.amdGpu.enable` | AMD GPU: VDPAU, VAAPI, 32-bit drivers, optional early KMS |
| `relics-pipewire` | `stc.pipewire.enable` | Pipewire: RTKit + ALSA 32-bit + PulseAudio compat |
| `relics-plasma6` | `stc.plasma6.enable` | KDE Plasma 6 Wayland desktop (SDDM + XDG portal) |
| `relics-yubikey-system` | `stc.yubikey.enable` | YubiKey system layer: pcscd + udev rules |
| `relics-traefik` | `stc.traefik.enable` | Native NixOS Traefik reverse proxy + Let's Encrypt |
| `relics-vaultwarden` | `stc.vaultwarden.enable` | Vaultwarden server (Bitwarden-compatible) |
| `relics-hardening-kernel` | `stc.hardening.kernel.enable` | Kernel sysctl (ASLR, kptr_restrict, dmesg, etc.) |
| `relics-hardening-network` | `stc.hardening.network.enable` | Network sysctl (anti-spoofing, SYN cookies, ICMP) |
| `relics-hardening-filesystem` | `stc.hardening.filesystem.enable` | /tmp noexec, /proc hidepid, /dev/shm restricted |
| `relics-hardening-ssh` | `stc.hardening.ssh.enable` | Hardened OpenSSH, key-only auth |
| `relics-docker-traefik` | `stc.docker.traefik.enable` | Traefik v3 reverse proxy container (Docker) |
| `relics-docker-crowdsec` | `stc.docker.crowdsec.enable` | CrowdSec WAF container |
| `relics-docker-notify` | `stc.docker.notify.enable` | Container failure notifications via ntfy |

## Home Manager Relics

| Module name | Enable option | Purpose |
|-------------|---------------|---------|
| `relics-kitty` | `stc.gui.kitty.enable` | Kitty terminal + Nerd Fonts |
| `relics-ghostty` | `stc.gui.ghostty.enable` | Ghostty terminal (GPU-accelerated, native GTK4) |
| `relics-zen-browser` | `stc.gui.zen-browser.enable` | Zen Browser |
| `relics-yubikey-user` | `stc.yubikey.enable` | YubiKey user tools: ykman, touch detector, OATH app |
| `relics-plasma-manager` | `stc.plasmaManager.enable` | Declarative KDE configuration via plasma-manager |

## See Also

- [Cogitator profiles](/stc/en/cogitator/) — composed relics for common use cases
- [Hardening relics](/stc/en/relics/hardening/) — all four hardening modules in detail
- [AMD GPU](/stc/en/relics/amd-gpu/) — GPU relic with gaming compatibility
- [Pipewire](/stc/en/relics/pipewire/) — audio relic
- [Plasma 6](/stc/en/relics/plasma6/) — KDE Plasma 6 desktop relic
- [YubiKey](/stc/en/relics/yubikey/) — two-relic YubiKey setup
- [Plasma Manager](/stc/en/relics/plasma-manager/) — declarative KDE configuration
- [Docker relics](/stc/en/relics/docker/) — Traefik, CrowdSec, and notify
- [AWS](/stc/en/relics/aws/) — EC2 drivers and AWS configuration
- [Traefik](/stc/en/relics/traefik/) — native NixOS reverse proxy
- [Vaultwarden](/stc/en/relics/vaultwarden/) — Bitwarden-compatible server
