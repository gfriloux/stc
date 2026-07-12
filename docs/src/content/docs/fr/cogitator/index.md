---
title: Profils Cogitator
description: Combinaisons pré-assemblées de reliques pour les cas d'usage courants — une seule option enable par profil.
sidebar:
  order: 0
---

Un profil Cogitator est une collection pré-assemblée de reliques, regroupées pour
un objectif commun. Là où une relique gère une seule préoccupation, un Cogitator
gère un scénario complet.

## Reliques vs Profils

| | Relique | Profil Cogitator |
|-|---------|-----------------|
| Portée | Une préoccupation | Plusieurs reliques combinées |
| Option d'activation | `stc.<module>.enable` | `stc.cogitator.<profil>.enable` ou `stc.cogitator.hardening.enable` |
| Utiliser quand | Tu as besoin d'un contrôle précis | Les valeurs par défaut sont suffisantes |
| Surchargeable | Toujours | Oui — les options des reliques individuelles s'appliquent toujours |

Quand tu actives un profil Cogitator, tu peux toujours régler les options des reliques
sous-jacentes. Le profil t'évite simplement d'activer chacune individuellement.

## Profils disponibles

### Profils NixOS

| Nom du module | Option d'activation | Ce qu'il compose |
|---------------|---------------------|------------------|
| `cogitator-hardening` | `stc.cogitator.hardening.enable` | Durcissement noyau + réseau + système de fichiers + SSH |
| `cogitator-vm` | `stc.cogitator.vm.enable` | Shell fish, SSH, utilisateur principal, Docker optionnel, GC Nix |
| `cogitator-docker-server` | `stc.cogitator.docker-server.enable` | Traefik + CrowdSec + notifications optionnelles + démon Docker |
| `cogitator-plasma` | `stc.cogitator.plasma.enable` | Bureau KDE Plasma 6 Wayland + audio Pipewire |
| `cogitator-gaming` | `stc.cogitator.gaming.enable` | GPU AMD + Pipewire + Steam |
| `cogitator-sarcophagus-kvm` | `stc.cogitator.sarcophagus-kvm.enable` | Image disque QEMU/KVM : ZFS + impermanence + durcissement + constructeur qcow2 |
| `cogitator-sarcophagus-aws` | `stc.cogitator.sarcophagus-aws.enable` | Image disque AMI AWS : ZFS + impermanence + durcissement + plateforme AWS + constructeur raw |
| `cogitator-dreadnought` | `stc.cogitator.dreadnought.enable` | Profil système EC2 : ZFS + impermanence + durcissement + plateforme AWS |

### Profils Home Manager

| Nom du module | Option d'activation | Ce qu'il compose |
|---------------|---------------------|------------------|
| `cogitator-enginseer` | `stc.cogitator.enginseer.enable` | Kit CLI complet (shell, outils dev, rites git) |
| `cogitator-desktop` | `stc.cogitator.desktop.enable` | kitty + zen-browser + GIMP + VLC |

## Quand utiliser les profils

Utilise un profil Cogitator quand :
- Tu veux la capacité complète avec une configuration minimale
- Les valeurs par défaut correspondent à tes besoins
- Tu configures une nouvelle machine rapidement

Utilise des reliques individuelles quand :
- Tu n'as besoin que d'une partie de ce qu'un profil fournit
- Tu dois surcharger des valeurs par défaut qui entrent en conflit avec ta configuration
- Tu veux comprendre exactement ce que fait chaque pièce avant de l'activer

## Voir aussi

- [Profil de durcissement](/stc/fr/cogitator/hardening/)
- [Profil VM](/stc/fr/cogitator/vm/)
- [Profil serveur Docker](/stc/fr/cogitator/docker-server/)
- [Profil bureau Plasma](/stc/fr/cogitator/plasma/)
- [Profil gaming](/stc/fr/cogitator/gaming/)
- [Profil Enginseer](/stc/fr/cogitator/enginseer/)
- [Profil Desktop](/stc/fr/cogitator/desktop/)
- [Profil Sarcophagus KVM](/stc/fr/cogitator/sarcophagus-kvm/)
- [Profil Sarcophagus AWS](/stc/fr/cogitator/sarcophagus-aws/)
- [Profil Dreadnought](/stc/fr/cogitator/dreadnought/)
