---
title: Boot
description: Configuration générique du chargeur de démarrage systemd-boot + EFI.
---

**Module :** `stc.nixosModules.relics-boot`

Configure le chargeur de démarrage. Rien de plus. Aucune sélection de noyau,
aucun support de système de fichiers — ce sont des préoccupations pour la relique
de la technologie concernée (`relics-zfs`, etc.).

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.boot.enable` | bool | `false` | Active la configuration systemd-boot + EFI |

## Ce qu'elle fait

Lorsqu'elle est activée :

- Pose `boot.loader.systemd-boot.enable = true`
- Pose `boot.loader.efi.canTouchEfiVariables = true`

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.relics-boot
  ./configuration.nix
];

# configuration.nix
{ stc.boot.enable = true; }
```

## À combiner avec

- [`relics-zfs`](/stc/fr/relics/zfs/) — noyau compatible ZFS, support des systèmes de fichiers, maintenance des pools
- [`relics-impermanence`](/stc/fr/relics/impermanence/) — rollback de la racine à chaque démarrage
