---
title: Impermanence
description: Impermanence basée sur ZFS — dataset racine rollbacké vers @blank à chaque démarrage.
---

**Module :** `stc.nixosModules.relics-impermanence`

Chaque démarrage est un nouveau départ. La machine oublie. Seul `/persist` se souvient.

Au premier démarrage, un snapshot `@blank` est pris automatiquement du dataset racine.
À chaque démarrage suivant, le dataset racine est rollbacké vers ce snapshot dans
l'initrd — avant que systemd ne démarre — de sorte que le système démarre toujours propre.

Tout ce qui doit survivre aux redémarrages doit être déclaré explicitement dans
`extraDirectories` ou `extraFiles`. Si ce n'est pas listé, c'est perdu après redémarrage.
C'est une fonctionnalité, pas un bug.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.impermanence.enable` | bool | `false` | Active l'impermanence basée sur ZFS |
| `stc.impermanence.poolName` | string | `"rpool"` | Pool ZFS contenant le dataset racine |
| `stc.impermanence.datasetName` | string | `"root"` | Dataset à rollbacker à chaque démarrage |
| `stc.impermanence.persistPath` | string | `"/persist"` | Point de montage du dataset ZFS persistant |
| `stc.impermanence.extraDirectories` | liste de strings | `[]` | Répertoires supplémentaires à bind-monter depuis `persistPath` vers `/` |
| `stc.impermanence.extraFiles` | liste de strings | `[]` | Fichiers supplémentaires à bind-monter depuis `persistPath` vers `/` |

## Ce qu'elle fait

**Service de rollback** — un service systemd stage-1 initrd (`zfs-rollback`) qui s'exécute
après l'import du pool ZFS mais avant le montage du système de fichiers racine. Au premier
démarrage il crée `poolName/datasetName@blank`. À chaque démarrage suivant il revient
à ce snapshot.

**Montage persistant** — monte `poolName/persist` à `persistPath` avec
`neededForBoot = true`, pour que les clés SSH et les secrets soient disponibles tôt.

**Chemins toujours persistants** — les chemins suivants sont toujours persistés,
quel que soit `extraDirectories` / `extraFiles` :

| Chemin | Pourquoi |
|--------|----------|
| `/var/lib/nixos` | Suivi UID/GID NixOS entre les activations |
| `/var/log` | Journaux pour l'audit et le débogage |
| `/etc/machine-id` | Identité systemd stable (journald se casse si ça change) |
| `/etc/ssh/ssh_host_rsa_key` (et `.pub`) | Clés d'hôte SSH |
| `/etc/ssh/ssh_host_ed25519_key` (et `.pub`) | Clés d'hôte SSH |

## Exemple d'utilisation

```nix
# flake.nix
modules = [
  stc.inputs.impermanence.nixosModules.impermanence  # module impermanence upstream
  stc.nixosModules.relics-impermanence
  ./configuration.nix
];

# configuration.nix
{
  stc.impermanence = {
    enable = true;
    poolName = "vmpool";      # doit correspondre à ton layout disko
    # datasetName = "root";   # la valeur par défaut convient si ton dataset est poolName/root
    # persistPath = "/persist"; # la valeur par défaut convient

    extraDirectories = [
      "/var/db/sudo/lectured"   # état de la lecture sudo
      "/var/lib/docker"         # données Docker (si tu utilises Docker)
    ];

    extraFiles = [
      "/etc/nix/id_rsa"         # exemple : une clé de déploiement
    ];
  };
}
```

:::caution[Importer le module upstream]
`relics-impermanence` nécessite le module NixOS `impermanence` upstream.
Importe-le via `stc.inputs.impermanence.nixosModules.impermanence` ou depuis
ton propre input flake `impermanence`.
:::

:::tip[initrd systemd]
Le rollback s'exécute dans l'initrd systemd stage-1. Cela signifie que
`boot.initrd.systemd.enable` est posé à `true` par cette relique. L'ancien
hook `postDeviceCommands` n'est pas utilisé.
:::

## À combiner avec

- [`relics-boot`](/stc/fr/relics/boot/) — requis pour le support ZFS dans l'initrd
- [`forge/layouts/zfs-local-vm`](/stc/fr/forge/layouts/) — crée le pool ZFS et les datasets
