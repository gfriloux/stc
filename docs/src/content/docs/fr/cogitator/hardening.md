---
title: Profil de durcissement
description: cogitator-hardening — active les quatre reliques de durcissement avec une seule option.
---

**Module :** `stc.nixosModules.cogitator-hardening`

Une option pour tous les durcir. Active le durcissement noyau, réseau, système de
fichiers et SSH en un seul interrupteur. Pour un contrôle chirurgical, utilise les
reliques individuelles à la place et active-les indépendamment.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.hardening.enable` | bool | `false` | Active la suite de durcissement complète (noyau + réseau + système de fichiers + SSH) |

## Ce qu'il compose

Activer `stc.hardening.enable = true` est équivalent à poser les quatre options suivantes :

```nix
stc.hardening.kernel.enable = true;
stc.hardening.network.enable = true;
stc.hardening.filesystem.enable = true;
stc.hardening.ssh.enable = true;
```

Les options des reliques individuelles — `allowedTCPPorts`, `tmpSize`, `allowedTCPForwarding` — restent
entièrement configurables. Le profil ne pose que les flags `enable`.

## Exemple d'utilisation

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-hardening
  ./configuration.nix
];

# configuration.nix
{
  stc.hardening.enable = true;

  # Ouvrir des ports supplémentaires au-delà de SSH (22)
  stc.hardening.network.allowedTCPPorts = [ 22 80 443 ];

  # Augmenter la taille de /tmp sur les machines riches en mémoire
  stc.hardening.filesystem.tmpSize = "4G";
}
```

## Voir aussi

- [Reliques de durcissement](/stc/fr/relics/hardening/) — documentation détaillée de chaque relique individuelle
