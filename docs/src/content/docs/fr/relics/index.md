---
title: Reliques
description: Vue d'ensemble des modules atomiques STC — une préoccupation par relique, tout sous le namespace stc.*.
sidebar:
  order: 0
---

Une relique est un module NixOS ou Home Manager atomique avec une seule responsabilité.
Chaque relique est autonome : elle déclare ses options, applique sa configuration,
et ne fait rien d'autre. Rien n'est activé par défaut.

## Le namespace stc.*

Toutes les options des reliques vivent sous `stc.*`. Chaque relique possède son propre
sous-namespace :

```nix
stc.boot.enable = true;
stc.zfs.enable = true;
stc.networking.enable = true;
stc.hardening.kernel.enable = true;
stc.docker.traefik.enable = true;
stc.gui.kitty.enable = true;
```

Ce namespace est isolé des options NixOS et Home Manager. Pas de collision.

## Comment utiliser une relique

1. Importe le module dans ton `nixosSystem` ou `homeManagerConfiguration`
2. Pose `enable = true` dans ta configuration

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

## Reliques NixOS

| Nom du module | Option d'activation | Objet |
|---------------|---------------------|-------|
| `relics-boot` | `stc.boot.enable` | systemd-boot + EFI (chargeur de démarrage uniquement) |
| `relics-zfs` | `stc.zfs.enable` | Noyau compatible ZFS, scrub auto, TRIM, ZED |
| `relics-networking` | `stc.networking.enable` | DHCP, DNS Quad9, domaine de recherche |
| `relics-impermanence` | `stc.impermanence.enable` | Rollback ZFS au démarrage, chemins persistants |
| `relics-aws` | `stc.aws.enable` | Drivers EC2, NTP AWS, console série, extension EBS |
| `relics-traefik` | `stc.traefik.enable` | Reverse proxy Traefik natif NixOS + Let's Encrypt |
| `relics-vaultwarden` | `stc.vaultwarden.enable` | Serveur Vaultwarden (Bitwarden-compatible) |
| `relics-hardening-kernel` | `stc.hardening.kernel.enable` | Sysctl noyau (ASLR, kptr_restrict, dmesg, etc.) |
| `relics-hardening-network` | `stc.hardening.network.enable` | Sysctl réseau (anti-spoofing, SYN cookies, ICMP) |
| `relics-hardening-filesystem` | `stc.hardening.filesystem.enable` | /tmp noexec, /proc hidepid, /dev/shm restreint |
| `relics-hardening-ssh` | `stc.hardening.ssh.enable` | OpenSSH durci, auth par clé uniquement |
| `relics-docker-traefik` | `stc.docker.traefik.enable` | Conteneur reverse proxy Traefik v3 (Docker) |
| `relics-docker-crowdsec` | `stc.docker.crowdsec.enable` | Conteneur WAF CrowdSec |
| `relics-docker-notify` | `stc.docker.notify.enable` | Notifications d'échec de conteneur via ntfy |

## Reliques Home Manager

| Nom du module | Option d'activation | Objet |
|---------------|---------------------|-------|
| `relics-kitty` | `stc.gui.kitty.enable` | Terminal Kitty + Nerd Fonts |
| `relics-zen-browser` | `stc.gui.zen-browser.enable` | Zen Browser |

## Voir aussi

- [Profils Cogitator](/fr/cogitator/) — reliques composées pour les cas d'usage courants
- [Reliques de durcissement](/fr/relics/hardening/) — les quatre modules de durcissement en détail
- [Reliques Docker](/fr/relics/docker/) — Traefik, CrowdSec et notify
- [AWS](/fr/relics/aws/) — drivers EC2 et configuration AWS
- [Traefik](/fr/relics/traefik/) — reverse proxy natif NixOS
- [Vaultwarden](/fr/relics/vaultwarden/) — serveur Bitwarden-compatible
