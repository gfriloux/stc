---
title: ZFS
description: Noyau ZFS, support au démarrage et maintenance des pools — scrub, TRIM, ZED.
---

**Module :** `stc.nixosModules.relics-zfs`

Tout ce dont NixOS a besoin pour faire tourner ZFS : le bon noyau, le support des
systèmes de fichiers dans l'initrd, les paramètres d'import des pools, et la
maintenance continue (scrub, TRIM, ZED).

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.zfs.enable` | bool | `false` | Active le noyau ZFS, le support au démarrage et la maintenance des pools |
| `stc.relics.zfs.kernel` | enum `"lts"` \| `"latest"` | `"lts"` | Quel noyau compatible ZFS suivre. `"lts"` = dernier LTS (stable, peu de churn) ; `"latest"` = dernier compatible (suit nixpkgs de près). |
| `stc.relics.zfs.scrubInterval` | string | `"monthly"` | Expression de calendrier systemd pour le scrub automatique |
| `stc.relics.zfs.autoSnapshot.enable` | bool | `false` | Active les snapshots périodiques ZFS sur le dataset persist |
| `stc.relics.zfs.autoSnapshot.daily` | int | `7` | Nombre de snapshots journaliers à conserver |
| `stc.relics.zfs.autoSnapshot.poolName` | string | — | Nom du pool ZFS (requis si autoSnapshot.enable = true) |

## Ce qu'elle fait

**Noyau** — sélectionne un noyau compatible avec le module ZFS hors-arbre (ZFS peut
prendre du retard sur le noyau ; une paire non assortie échoue à compiler). Avec
`kernel = "lts"` (défaut), il choisit la dernière série LTS compatible ZFS — stable
et peu de churn, le bon choix en production. Avec `kernel = "latest"`, il choisit le
dernier noyau compatible, suivant nixpkgs de près. Les LTS restent compatibles ZFS le
plus longtemps ; les noyaux non-LTS atteignent souvent l'EOL avant que ZFS ne supporte
le suivant.

**Support système de fichiers** — ajoute `"zfs"` à `boot.supportedFilesystems` et
`boot.initrd.supportedFilesystems` pour que l'initrd puisse importer les pools au
démarrage.

**Import des pools** — pose `boot.zfs.forceImportRoot = lib.mkDefault false` :
le pool racine est importé **sans** `-f`, donc ZFS conserve le contrôle qui
refuse un pool dont le hostId appartient à un autre système. `forceImportAll`
reste `false` lui aussi, pour les pools non-racine.

**Scrub automatique** — exécute `zpool scrub` sur tous les pools à `scrubInterval`.
Mensuel suffit pour la plupart des charges de travail ; passe à `"weekly"` sur les
systèmes à forte écriture ou les grands pools.

**TRIM** — envoie des commandes discard aux SSD et aux disques virtuels à
provisionnement fin, récupérant de l'espace et maintenant les performances d'écriture.

**ZED (ZFS Event Daemon)** — surveille la santé des pools et journalise les erreurs.

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.relics-boot
  stc.nixosModules.relics-zfs
  ./configuration.nix
];

# configuration.nix
{
  stc.relics.boot.enable = true;
  stc.relics.zfs = {
    enable = true;

    # Optionnel : snapshots périodiques
    autoSnapshot = {
      enable = true;
      poolName = "vmpool";   # snapshots activés sur vmpool/persist uniquement
      daily = 14;            # optionnel : garder 14 jours au lieu de 7
    };

    # Optionnel : scrub hebdomadaire sur les pools à forte écriture
    scrubInterval = "weekly";
  };

  # ZFS nécessite un hostId unique par machine.
  # Génère : head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
  networking.hostId = "a1b2c3d4";
}
```

:::tip[Format de scrubInterval]
La valeur est une expression de calendrier systemd. Les valeurs valides incluent
`"daily"`, `"weekly"`, `"monthly"`, ou une expression complète comme
`"Sun *-*-* 02:00:00"`.
:::

:::note[ZFS hostId]
ZFS utilise `networking.hostId` pour identifier le système qui importe le pool.
Cela empêche qu'un pool utilisé en dernier sur la machine A soit silencieusement
importé sur la machine B. Génère une chaîne hexadécimale de 8 caractères unique
pour chaque machine.

STC ne fixe **aucun** hostId par défaut. [srvos](https://github.com/nix-community/srvos)
le fige à `8425e349`, celui de l'ISO d'installation, pour que l'import tombe
toujours juste : ça supprime la divergence ponctuelle, au prix de faire porter la
même identité à toutes les machines — deux d'entre elles importeraient le même
pool sans que ZFS n'objecte. Un hostId unique par machine est la moitié stricte
qui donne sa valeur à l'import non forcé.
:::

:::caution[Si votre pool racine porte un hostId étranger]
Un pool importé en dernier par un autre système — un disque déplacé d'une machine
à l'autre, un pool créé par un installateur et jamais exporté — refusera
désormais de s'importer, et l'hôte s'arrête dans l'initrd au lieu de démarrer.
Deux sorties :

- **Ponctuelle, au bootloader :** ajoutez `zfs_force=1` à la ligne de commande du
  noyau pour un seul démarrage, puis `zpool export <pool>` et laissez le boot
  suivant l'importer proprement. Les deux implémentations de stage 1 (scriptée et
  systemd) honorent le paramètre.
- **Permanente, si votre installation l'exige vraiment :** posez
  `boot.zfs.forceImportRoot = true;` dans votre configuration. La valeur de la
  relique est un `mkDefault`, donc une définition nue l'emporte — pas besoin de
  `lib.mkForce`. Écrire `lib.mkDefault true` entrerait en conflit avec le
  `mkDefault` de la relique et casserait l'évaluation.

Une installation avec `nixos-anywhere` (aucun schematic STC n'emprunte ce chemin,
tous les trois construisent une image) laisse le pool importé avec le hostId de
l'installateur. Lancez `zpool export <pool>` avant le premier redémarrage et
l'import n'aura besoin d'aucune force. L'amont fait de `false` le défaut à partir
du `stateVersion` 26.11 : c'est la direction que prend NixOS de toute façon.
:::

## À combiner avec

- [`relics-boot`](/stc/fr/relics/boot/) — chargeur de démarrage systemd-boot + EFI
- [`relics-impermanence`](/stc/fr/relics/impermanence/) — rollback de la racine à chaque démarrage
- [`forge/layouts/zfs-local-vm`](/stc/fr/forge/layouts/) — layout de disque disko
