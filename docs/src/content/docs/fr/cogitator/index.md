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
| Option d'activation | `stc.<module>.enable` | `stc.cogitator.<profil>.enable` ou `stc.hardening.enable` |
| Utiliser quand | Tu as besoin d'un contrôle précis | Les valeurs par défaut sont suffisantes |
| Surchargeable | Toujours | Oui — les options des reliques individuelles s'appliquent toujours |

Quand tu actives un profil Cogitator, tu peux toujours régler les options des reliques
sous-jacentes. Le profil t'évite simplement d'activer chacune individuellement.

## Profils disponibles

### Profils NixOS

| Nom du module | Option d'activation | Ce qu'il compose |
|---------------|---------------------|------------------|
| `cogitator-hardening` | `stc.hardening.enable` | Durcissement noyau + réseau + système de fichiers + SSH |
| `cogitator-vm` | `stc.cogitator.vm.enable` | Shell fish, SSH, utilisateur principal, Docker optionnel, GC Nix |
| `cogitator-docker-server` | `stc.cogitator.docker-server.enable` | Traefik + CrowdSec + ntfy + démon Docker |

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

- [Profil de durcissement](/fr/cogitator/hardening/)
- [Profil VM](/fr/cogitator/vm/)
- [Profil serveur Docker](/fr/cogitator/docker-server/)
- [Profil Enginseer](/fr/cogitator/enginseer/)
- [Profil Desktop](/fr/cogitator/desktop/)
