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
stc.relics.boot.enable = true;
stc.relics.zfs.enable = true;
stc.relics.networking.enable = true;
stc.relics.hardening.kernel.enable = true;
stc.relics.docker.traefik.enable = true;
stc.relics.gui.kitty.enable = true;
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
  stc.relics.boot.enable = true;
  stc.relics.zfs.enable = true;
  stc.relics.zfs.scrubInterval = "weekly";
}
```

## Reliques NixOS

| Nom du module | Option d'activation | Objet |
|---------------|---------------------|-------|
| `relics-boot` | `stc.relics.boot.enable` | systemd-boot + EFI (chargeur de démarrage uniquement) |
| `relics-zfs` | `stc.relics.zfs.enable` | Noyau compatible ZFS, scrub auto, TRIM, ZED |
| `relics-networking` | `stc.relics.networking.enable` | DHCP, DNS Quad9, domaine de recherche |
| `relics-impermanence` | `stc.relics.impermanence.enable` | Rollback ZFS au démarrage, chemins persistants |
| `relics-aws` | `stc.relics.aws.enable` | Drivers EC2, NTP AWS, console série, extension EBS |
| `relics-amd-gpu` | `stc.relics.amdGpu.enable` | GPU AMD : VDPAU, VAAPI, pilotes 32 bits, KMS précoce optionnel |
| `relics-pipewire` | `stc.relics.pipewire.enable` | Pipewire : RTKit + ALSA 32 bits + compat PulseAudio |
| `relics-plasma6` | `stc.relics.plasma6.enable` | Bureau KDE Plasma 6 Wayland (SDDM + portail XDG) |
| `relics-yubikey-system` | `stc.relics.yubikey.enable` | Couche système YubiKey : pcscd + règles udev |
| `relics-traefik` | `stc.relics.traefik.enable` | Reverse proxy Traefik natif NixOS + Let's Encrypt |
| `relics-vaultwarden` | `stc.relics.vaultwarden.enable` | Serveur Vaultwarden (Bitwarden-compatible) |
| `relics-hardening-kernel` | `stc.relics.hardening.kernel.enable` | Sysctl noyau (ASLR, kptr_restrict, dmesg, etc.) |
| `relics-hardening-network` | `stc.relics.hardening.network.enable` | Sysctl réseau (anti-spoofing, SYN cookies, ICMP) |
| `relics-hardening-filesystem` | `stc.relics.hardening.filesystem.enable` | /tmp noexec, /proc hidepid, /dev/shm restreint |
| `relics-hardening-ssh` | `stc.relics.hardening.ssh.enable` | OpenSSH durci, auth par clé uniquement |
| `relics-docker-traefik` | `stc.relics.docker.traefik.enable` | Conteneur reverse proxy Traefik v3 (Docker) |
| `relics-docker-socket-proxy` | `stc.relics.docker.socketProxy.enable` | Proxy filtrant devant le socket Docker |
| `relics-docker-crowdsec` | `stc.relics.docker.crowdsec.enable` | Conteneur IDS/IPS CrowdSec |
| `relics-docker-notify` | `stc.relics.docker.notify.enable` | Notifications d'échec de conteneur via ntfy |

## Reliques Home Manager

| Nom du module | Option d'activation | Objet |
|---------------|---------------------|-------|
| `relics-kitty` | `stc.relics.gui.kitty.enable` | Terminal Kitty + Nerd Fonts |
| `relics-ghostty` | `stc.relics.gui.ghostty.enable` | Terminal Ghostty (accéléré GPU, GTK4 natif) |
| `relics-zen-browser` | `stc.relics.gui.zen-browser.enable` | Zen Browser |
| `relics-yubikey-user` | `stc.relics.yubikey.enable` | Outils utilisateur YubiKey : ykman, détecteur de toucher, app OATH |
| `relics-plasma-manager` | `stc.relics.plasmaManager.enable` | Configuration KDE déclarative via plasma-manager |

## Voir aussi

- [Profils Cogitator](/stc/fr/cogitator/) — reliques composées pour les cas d'usage courants
- [Reliques de durcissement](/stc/fr/relics/hardening/) — les quatre modules de durcissement en détail
- [AMD GPU](/stc/fr/relics/amd-gpu/) — relique GPU avec compatibilité gaming
- [Pipewire](/stc/fr/relics/pipewire/) — relique audio
- [Plasma 6](/stc/fr/relics/plasma6/) — relique bureau KDE Plasma 6
- [YubiKey](/stc/fr/relics/yubikey/) — configuration YubiKey en deux reliques
- [Plasma Manager](/stc/fr/relics/plasma-manager/) — configuration KDE déclarative
- [Reliques Docker](/stc/fr/relics/docker/) — Traefik, socket-proxy, CrowdSec et notify
- [AWS](/stc/fr/relics/aws/) — drivers EC2 et configuration AWS
- [Traefik](/stc/fr/relics/traefik/) — reverse proxy natif NixOS
- [Vaultwarden](/stc/fr/relics/vaultwarden/) — serveur Bitwarden-compatible
