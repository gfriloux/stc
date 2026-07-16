---
title: Profil de durcissement
description: cogitator-hardening — active les cinq reliques de durcissement avec une seule option.
---

**Module :** `stc.nixosModules.cogitator-hardening`

Une option pour tous les durcir. Active le durcissement noyau, réseau, système de
fichiers, SSH et la blacklist de modules en un seul interrupteur. Pour un contrôle
chirurgical, utilise les reliques individuelles à la place et active-les
indépendamment.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.hardening.enable` | bool | `false` | Active la suite de durcissement complète (noyau + réseau + système de fichiers + SSH + blacklist de modules) |

## Ce qu'il compose

Activer `stc.cogitator.hardening.enable = true` est équivalent à poser les cinq options suivantes :

```nix
stc.relics.hardening.kernel.enable = true;
stc.relics.hardening.network.enable = true;
stc.relics.hardening.filesystem.enable = true;
stc.relics.hardening.ssh.enable = true;
stc.relics.hardening.modules.enable = true;
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
  stc.cogitator.hardening.enable = true;

  # Ouvrir des ports supplémentaires au-delà de SSH (22)
  stc.relics.hardening.network.allowedTCPPorts = [ 22 80 443 ];

  # Augmenter la taille de /tmp sur les machines riches en mémoire
  stc.relics.hardening.filesystem.tmpSize = "4G";
}
```

## Voir aussi

- [Reliques de durcissement](/stc/fr/relics/hardening/) — documentation détaillée de chaque relique individuelle
