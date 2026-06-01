---
title: Cogitator Profiles
description: Pre-assembled combinations of relics for common use cases — one enable option per profile.
sidebar:
  order: 0
---

A Cogitator profile is a pre-assembled collection of relics, grouped for a common
purpose. Where a relic handles a single concern, a Cogitator handles a complete
scenario.

## Relics vs Profiles

| | Relic | Cogitator Profile |
|-|-------|-------------------|
| Scope | One concern | Multiple relics combined |
| Enable option | `stc.<module>.enable` | `stc.cogitator.<profile>.enable` or `stc.hardening.enable` |
| Use when | You need precise control | Defaults are good enough |
| Overridable | Always | Yes — individual relic options still apply |

When you enable a Cogitator profile, you can still tune the underlying relic
options. The profile just saves you from enabling each one individually.

## Available Profiles

### NixOS Profiles

| Module name | Enable option | What it composes |
|-------------|---------------|------------------|
| `cogitator-hardening` | `stc.hardening.enable` | kernel + network + filesystem + SSH hardening |
| `cogitator-vm` | `stc.cogitator.vm.enable` | fish shell, SSH, primary user, optional Docker, Nix GC |
| `cogitator-docker-server` | `stc.cogitator.docker-server.enable` | Traefik + CrowdSec + ntfy + Docker daemon |
| `cogitator-plasma` | `stc.cogitator.plasma.enable` | KDE Plasma 6 Wayland desktop + Pipewire audio |
| `cogitator-gaming` | `stc.cogitator.gaming.enable` | AMD GPU + Pipewire + Steam |

### Home Manager Profiles

| Module name | Enable option | What it composes |
|-------------|---------------|------------------|
| `cogitator-enginseer` | `stc.cogitator.enginseer.enable` | Full CLI toolkit (shell, dev tools, git rites) |
| `cogitator-desktop` | `stc.cogitator.desktop.enable` | kitty + zen-browser + GIMP + VLC |

## When to Use Profiles

Use a Cogitator profile when:
- You want the full capability with minimal configuration
- The defaults match your requirements
- You are setting up a new machine quickly

Use individual relics when:
- You need only part of what a profile provides
- You need to override defaults that conflict with your setup
- You want to understand exactly what each piece does before enabling it

## See Also

- [Hardening profile](/stc/en/cogitator/hardening/)
- [VM profile](/stc/en/cogitator/vm/)
- [Docker server profile](/stc/en/cogitator/docker-server/)
- [Plasma desktop profile](/stc/en/cogitator/plasma/)
- [Gaming profile](/stc/en/cogitator/gaming/)
- [Enginseer profile](/stc/en/cogitator/enginseer/)
- [Desktop profile](/stc/en/cogitator/desktop/)
