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
| `stc.relics.impermanence.enable` | bool | `false` | Active l'impermanence basée sur ZFS |
| `stc.relics.impermanence.poolName` | string | `"rpool"` | Pool ZFS contenant le dataset racine |
| `stc.relics.impermanence.datasetName` | string | `"root"` | Dataset à rollbacker à chaque démarrage |
| `stc.relics.impermanence.persistPath` | string | `"/persist"` | Point de montage du dataset ZFS persistant |
| `stc.relics.impermanence.persistDataset` | string | `"persist"` | Nom du dataset ZFS persistant sous `poolName`, monté sur `persistPath` |
| `stc.relics.impermanence.extraDirectories` | liste de strings | `[]` | Répertoires supplémentaires à bind-monter depuis `persistPath` vers `/` |
| `stc.relics.impermanence.extraFiles` | liste de strings | `[]` | Fichiers supplémentaires à bind-monter depuis `persistPath` vers `/` |
| `stc.relics.impermanence.onRollbackFailure` | `"continue"` \| `"emergency"` | `"continue"` | Ce qu'un rollback en échec fait au démarrage — voir [Quand le rollback échoue](#quand-le-rollback-échoue) |

## Ce qu'elle fait

**Service de rollback** — un service systemd stage-1 initrd (`zfs-rollback`) qui s'exécute
après l'import du pool ZFS mais avant le montage du système de fichiers racine. Au premier
démarrage il crée `poolName/datasetName@blank`. À chaque démarrage suivant il revient
à ce snapshot.

**Compte rendu du résultat** — `stc-impermanence-state.service` dans le système démarré,
qui lit ce que l'initrd a laissé dans `/run` et échoue si le rollback a échoué.

**Montage persistant** — monte `poolName/persistDataset` (par défaut `poolName/persist`)
à `persistPath` avec `neededForBoot = true`, pour que les clés SSH et les secrets
soient disponibles tôt.

**Chemins toujours persistants** — les chemins suivants sont toujours persistés,
quel que soit `extraDirectories` / `extraFiles` :

| Chemin | Pourquoi |
|--------|----------|
| `/var/lib/nixos` | Suivi UID/GID NixOS entre les activations |
| `/var/log` | Journaux pour l'audit et le débogage |
| `/etc/machine-id` | Identité systemd stable (journald se casse si ça change) |
| `/etc/ssh/ssh_host_rsa_key` (et `.pub`) | Clés d'hôte SSH |
| `/etc/ssh/ssh_host_ed25519_key` (et `.pub`) | Clés d'hôte SSH |

## Quand le rollback échoue

La promesse en tête de page est une promesse d'intégrité : une machine qui
démarre propre est une machine sur laquelle un attaquant ne persiste pas en
écrivant dans la racine. Un rollback qui échoue casse cette promesse — l'hôte
monte en portant tout ce que le boot précédent y a laissé.

**Par défaut, le boot continue.** `onRollbackFailure = "continue"` garde l'hôte
joignable, ce qui est presque toujours ce qu'on veut sur un serveur devant lequel
on ne peut pas s'asseoir. Ce qui change, c'est que l'échec n'est plus silencieux :

- le script d'initrd laisse un marqueur dans `/run`, qui survit au `switch-root` ;
- `stc-impermanence-state.service` le lit et **échoue**, donc l'unité apparaît
  dans `systemctl --failed` et `systemctl is-system-running` répond `degraded`.

Ça compte parce que l'unité `zfs-rollback` elle-même n'a aucun fragment dans le
système démarré — avant ça, un rollback raté ne laissait qu'une ligne dans un
journal d'initrd que personne ne lit.

**Si vous préférez ne pas démarrer du tout**, posez :

```nix
stc.relics.impermanence.onRollbackFailure = "emergency";
```

Le service de rollback tire alors `emergency.target` depuis l'initrd et le boot
s'arrête. Connaissez le prix d'abord : `boot.initrd.systemd.emergencyAccess` vaut
`null` par défaut, c'est-à-dire **aucun shell** à l'invite d'urgence. Un hôte
headless qui atterrit là se récupère hors bande. Posez `emergencyAccess` avec, si
vous voulez pouvoir reprendre la main.

## Si `@blank` disparaît

Le snapshot est créé automatiquement quand il est absent, parce que rien d'autre
ne le crée — les builders d'image n'en livrent aucun, donc sans ça un disque neuf
ne démarrerait jamais.

La conséquence mérite d'être dite franchement, parce que c'est la seule façon
dont cette relique peut casser sa promesse en signalant un succès. Si `@blank`
est détruit — à la main, ou en restaurant un pool depuis un `zfs send` qui ne
l'incluait pas — le boot suivant prend un **nouveau** snapshot du dataset racine
*tel qu'il est à cet instant*, et celui-ci devient la définition permanente de
« propre » pour tous les boots d'après. Si la racine était sale, elle le reste,
pour toujours, et le rollback continue de réussir.

La relique ne sait pas distinguer un vrai premier boot d'une référence perdue,
alors elle ne devine pas. Elle le dit, deux fois : un avertissement dans le
journal d'initrd nommant le dataset, et un second marqueur qui fait journaliser
la même chose à `stc-impermanence-state.service` dans le système démarré. Voir ce
message sur un hôte qui n'est pas en cours d'installation veut dire que la
référence propre a disparu et qu'il faut la rétablir délibérément.

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
  stc.relics.impermanence = {
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
