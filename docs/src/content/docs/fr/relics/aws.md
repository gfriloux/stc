---
title: AWS
description: Configuration AWS EC2 — drivers Nitro/Xen, NTP, console série, expansion EBS et pools ZFS.
---

**Module :** `stc.nixosModules.relics-aws`

Configure automatiquement NixOS pour tourner sur AWS EC2. Charge les drivers requis (NVMe, ENA), configure la console série pour AWS Systems Manager ou EC2 Connect, synchronise l'heure via le serveur NTP interne AWS, et étend les pools ZFS quand le volume EBS est agrandi.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.aws.enable` | bool | `false` | Active la configuration AWS EC2. |
| `stc.relics.aws.poolName` | string | — | Nom du pool ZFS à étendre lors de l'expansion de l'EBS. **Requis.** |
| `stc.relics.aws.ebsDisk` | string | `"nvme0n1"` | Périphérique de bloc EBS (sans `/dev/`). `nvme0n1` pour instances Nitro, `xvda` pour Xen. |
| `stc.relics.aws.ebsPartition` | int | `3` | Numéro de partition contenant le pool ZFS. Par défaut : schéma make-single-disk-zfs-image (bios_grub=1, ESP=2, ZFS=3). |

## Ce qu'il fait

- **Drivers au démarrage :** Charge `nvme`, `ena`, `xen_blkfront` (Nitro et Xen)
- **Blackliste xen_fbfront :** Évite un délai de 30 secondes au boot sur instances Xen
- **Console série :** Active `ttyS0` pour AWS Systems Manager ou EC2 Connect (accès sans clé SSH)
- **Timeouts NVMe :** Configure `nvme_core.io_timeout=4294967295` (recommandation Amazon EBS)
- **Confiance RNG CPU :** Pose `random.trust_cpu=on` pour éviter la pénurie d'entropie au premier boot sur instances headless. Trade-off : fait confiance au RNG du fondeur — raisonnable quand on fait déjà confiance à l'hyperviseur ; à retirer si ton modèle de menace diffère.
- **NTP interne AWS :** Utilise `169.254.169.123` — toujours accessible, pas d'accès internet requis
- **Désactive udisks2 :** Supprime les dépendances GTK inutiles sur serveur headless
- **Udev rules :** Installe `amazon-ec2-utils` pour compatibilité complète
- **Expansion EBS :** Oneshot au démarrage (`stc-grow-pool`) qui étend la partition et le pool ZFS quand le volume EBS est plus grand que l'image buildée. S'exécute à chaque boot (pour prendre en compte un volume redimensionné) mais **pas** à chaque `nixos-rebuild switch`, et remonte les vraies erreurs `growpart` au lieu de les avaler

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.relics-zfs
  stc.nixosModules.relics-aws
];

{
  stc.relics.zfs.enable = true;
  stc.relics.aws = {
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
  stc.relics.aws = {
    enable = true;
    poolName = "rpool";
    ebsDisk = "xvda";
    ebsPartition = 3;
  };
}
```

## À combiner avec

- **[relics-zfs](/stc/fr/relics/zfs)** (requis) — Pool ZFS pour l'expansion EBS
- **[relics-impermanence](/stc/fr/relics/impermanence)** — Recommandé pour rootfs éphémère en EC2
- **schematic aws-ami** — Template pour builder des AMI NixOS
