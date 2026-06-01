---
title: Layouts
description: Layouts de partitions Disko pour les machines gérées par STC.
---

Les layouts Forge sont des définitions de partitions [Disko](https://github.com/nix-community/disko).
Ce sont des fonctions Nix pures — appelle-les avec tes paramètres et inclus le résultat
dans ta liste de modules `nixosSystem`.

## zfs-local-vm

**Fonction :** `stc.lib.layouts.zfs-local-vm`

**Signature :** `{ poolName ? "vmpool" }`

Layout de disque pour une machine virtuelle QEMU/KVM locale. Cible `/dev/vda`
(périphérique virtio-blk). À combiner avec `relics-boot` et `relics-impermanence`.

### Table de partitions

| Partition | Taille | Type | Montage |
|-----------|--------|------|---------|
| ESP | 1 Gio | vfat | `/boot` |
| ZFS | Reste | ZFS | — |

### Pool ZFS

| Dataset | Montage | Objet |
|---------|---------|-------|
| `poolName/root` | `/` | Racine éphémère — rollbackée vers `@blank` à chaque démarrage |
| `poolName/nix` | `/nix` | Store Nix persistant |
| `poolName/persist` | `/persist` | État persistant explicite |

Options du pool : `ashift=12` (alignement secteur 4K), `compression=lz4`, `atime=off`,
`xattr=sa`, `acltype=posixacl`, tous les datasets utilisent les points de montage legacy.

Un snapshot `@blank` est créé sur `poolName/root` immédiatement après la création du pool
(`postCreateHook`). C'est le snapshot vers lequel `relics-impermanence` revient à chaque démarrage.

### Utilisation dans nixosSystem

```nix
# flake.nix
{ nixpkgs, stc, ... }:
{
  nixosConfigurations.my-vm = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      stc.inputs.disko.nixosModules.disko
      stc.inputs.impermanence.nixosModules.impermanence

      stc.nixosModules.relics-boot
      stc.nixosModules.relics-zfs
      stc.nixosModules.relics-impermanence

      # Layout de disque — appelle avec ton nom de pool
      (stc.lib.layouts.zfs-local-vm { poolName = "vmpool"; })

      ./configuration.nix
    ];
  };
}
```

```nix
# configuration.nix
{
  stc.boot.enable = true;
  stc.zfs.enable = true;
  stc.impermanence = {
    enable = true;
    poolName = "vmpool";   # doit correspondre à l'argument du layout
  };

  # Drivers virtio — nécessaires pour que /dev/vda existe dans l'initrd
  boot.initrd.kernelModules = [ "virtio_pci" "virtio_blk" ];

  # Les disques virtio n'ont pas d'entrées by-id dans QEMU
  boot.zfs.devNodes = "/dev";

  networking.hostName = "my-vm";
  networking.hostId = "a1b2c3d4";  # unique par machine
}
```

:::caution[Input Disko]
Le layout utilise des déclarations Disko. Tu dois inclure `stc.inputs.disko.nixosModules.disko`
dans ta liste de modules, ou fournir disko depuis tes propres inputs. Sans le module disko,
l'option `disko.devices` n'existe pas et l'évaluation échouera.
:::

:::tip[virtio et devNodes]
Les disques virtio QEMU ne créent pas d'entrées sous `/dev/disk/by-id/`. ZFS cherche là
par défaut. Pose `boot.zfs.devNodes = "/dev"` pour utiliser le chemin de périphérique
brut à la place. Ajoute aussi `virtio_pci` et `virtio_blk` à `boot.initrd.kernelModules`
pour que le disque soit visible dans l'initrd avant que ZFS ne tente d'importer le pool.
:::

## Voir aussi

- [Schématic : local-vm](/stc/fr/schematics/local-vm/) — exemple complet utilisant ce layout
- [relics-boot](/stc/fr/relics/boot/) — fournit le noyau ZFS
- [relics-impermanence](/stc/fr/relics/impermanence/) — utilise le snapshot `@blank` créé ici
