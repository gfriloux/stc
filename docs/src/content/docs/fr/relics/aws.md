---
title: AWS
description: Configuration AWS EC2 — drivers Nitro/Xen, NTP, console série, expansion EBS et pools ZFS.
---

**Module :** `stc.nixosModules.relics-aws`

Configure automatiquement NixOS pour tourner sur AWS EC2. Charge les drivers requis (NVMe, ENA), configure la console série pour AWS Systems Manager ou EC2 Connect, synchronise l'heure via le serveur NTP interne AWS, et étend les pools ZFS quand le volume EBS est agrandi.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.aws.enable` | bool | `false` | Active la configuration AWS EC2. |
| `stc.aws.poolName` | string | — | Nom du pool ZFS à étendre lors de l'expansion de l'EBS. **Requis.** |
| `stc.aws.ebsDisk` | string | `"nvme0n1"` | Périphérique de bloc EBS (sans `/dev/`). `nvme0n1` pour instances Nitro, `xvda` pour Xen. |
| `stc.aws.ebsPartition` | int | `3` | Numéro de partition contenant le pool ZFS. Par défaut : schéma make-single-disk-zfs-image (bios_grub=1, ESP=2, ZFS=3). |

## Ce qu'il fait

- **Drivers au démarrage :** Charge `nvme`, `ena`, `xen_blkfront` (Nitro et Xen)
- **Blackliste xen_fbfront :** Évite un délai de 30 secondes au boot sur instances Xen
- **Console série :** Active `ttyS0` pour AWS Systems Manager ou EC2 Connect (accès sans clé SSH)
- **Timeouts NVMe :** Configure `nvme_core.io_timeout=4294967295` (recommandation Amazon EBS)
- **NTP interne AWS :** Utilise `169.254.169.123` — toujours accessible, pas d'accès internet requis
- **Désactive udisks2 :** Supprime les dépendances GTK inutiles sur serveur headless
- **Udev rules :** Installe `amazon-ec2-utils` pour compatibilité complète
- **Expansion EBS :** Script d'activation qui étend la partition et le pool ZFS si le volume EBS est plus grand que l'image buildée

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.relics-zfs
  stc.nixosModules.relics-aws
];

{
  stc.zfs.enable = true;
  stc.aws = {
    enable = true;
    poolName = "rpool";
    # ebsDisk = "nvme0n1";      # défaut : Nitro
    # ebsPartition = 3;         # défaut : partition 3
  };
}
```

Pour Xen (instances plus anciennes) :

```nix
{
  stc.aws = {
    enable = true;
    poolName = "rpool";
    ebsDisk = "xvda";
    ebsPartition = 3;
  };
}
```

## À combiner avec

- **[relics-zfs](/fr/relics/zfs)** (requis) — Pool ZFS pour l'expansion EBS
- **[relics-impermanence](/fr/relics/impermanence)** — Recommandé pour rootfs éphémère en EC2
- **schematic aws-ami** — Template pour builder des AMI NixOS
