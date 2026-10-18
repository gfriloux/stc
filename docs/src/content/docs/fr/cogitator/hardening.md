---
title: Profil de durcissement
description: cogitator-hardening — active les six reliques de durcissement avec une seule option.
---

**Module :** `stc.nixosModules.cogitator-hardening`

Une option pour tous les durcir. Active le durcissement noyau, réseau, système de
fichiers, SSH, la blacklist de modules et l'accès aux ordonnanceurs en un seul
interrupteur. Pour un contrôle
chirurgical, utilise les reliques individuelles à la place et active-les
indépendamment.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.hardening.enable` | bool | `false` | Active la suite de durcissement complète (noyau + réseau + système de fichiers + SSH + blacklist de modules + accès aux ordonnanceurs) |

## Ce qu'il compose

Activer `stc.cogitator.hardening.enable = true` est équivalent à poser les six options suivantes :

```nix
stc.relics.hardening.kernel.enable = true;
stc.relics.hardening.network.enable = true;
stc.relics.hardening.filesystem.enable = true;
stc.relics.hardening.ssh.enable = true;
stc.relics.hardening.modules.enable = true;
stc.relics.hardening.scheduler.enable = true;
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

## Prendre la suite moins une partie

Depuis `v0.18.0`, les six sous-reliques sont activées avec `lib.mkDefault` : tu
peux garder l'interrupteur unique et décliner quand même l'une d'elles :

```nix
stc.cogitator.hardening.enable = true;

# Tu possèdes ta configuration sshd, ou tu gères toi-même la politique cron.
stc.relics.hardening.ssh.enable = false;
```

Avant `v0.18.0` il fallait `lib.mkForce`, ou renoncer à ce profil et importer les
six reliques à la carte. Voir
[Valeurs par défaut surchargeables](/stc/fr/reference/overridable-defaults/) pour
la règle et la liste complète.

## Voir aussi

- [Reliques de durcissement](/stc/fr/relics/hardening/) — documentation détaillée de chaque relique individuelle
- [Valeurs par défaut surchargeables](/stc/fr/reference/overridable-defaults/) — ce que ce profil épingle et ce qu'il ne fait que proposer
