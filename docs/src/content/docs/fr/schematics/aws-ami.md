---
title: aws-ami
description: Une AMI NixOS pour AWS EC2 avec ZFS, impermanence et durcissement.
---

**Source :** `schematics/aws-ami/`

Une image AMI NixOS pour AWS EC2, avec stockage ZFS, impermanence et durcissement
complet. L'AMI utilise le même layout de disque `zfs-local-vm` que le schématic
local-vm — la structure du pool ZFS est identique.

## Prérequis

### Configuration locale

- Nix avec les flakes activés
- AWS CLI configuré (`aws configure`)

### Configuration AWS unique

1. Créer un bucket S3 pour les uploads d'images
2. Créer le rôle IAM `vmimport` avec les permissions de la [documentation AWS VM Import](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html)

### Avant de builder

Dans `flake.nix`, modifie au minimum :

- `networking.hostId` — génère une valeur unique : `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
- `openssh.authorizedKeys.keys` — ajoute ta clé SSH publique

L'accès SSH par mot de passe est désactivé par `cogitator-hardening`. Sans clé SSH,
tu ne pourras pas te connecter à l'instance.

## Modules utilisés

| Module | Objet |
|--------|-------|
| `disko.nixosModules.disko` | Partitionnement déclaratif du disque |
| `stc.nixosModules.relics-boot` | systemd-boot + noyau compatible ZFS |
| `stc.nixosModules.relics-zfs` | Scrub auto, TRIM, ZED |
| `stc.nixosModules.relics-networking` | DHCP, DNS Quad9 |
| `stc.nixosModules.relics-impermanence` | Rollback racine à chaque démarrage |
| `stc.nixosModules.cogitator-hardening` | Suite de durcissement complète |
| `stc.lib.layouts.zfs-local-vm` | Layout disque EFI + ZFS |
| `./image.nix` | Builder d'image raw (override GRUB pour le build) |

## Modules noyau spécifiques AWS

Les instances AWS nécessitent des drivers pour le matériel Nitro (moderne) et Xen (legacy) :

```nix
# Instances Nitro : stockage NVMe + réseau ENA
# Instances Xen : périphérique bloc + frontend réseau
boot.initrd.availableKernelModules = [ "nvme" "xen_blkfront" ];
boot.kernelModules = [ "ena" "xen_netfront" ];
```

## Recettes du Justfile

```bash
just update    # met à jour les inputs du flake

just build     # construit result/nixos.root.img (format raw, ~5-10 minutes)
just run       # boot l'image dans QEMU/KVM pour test local
just ssh       # SSH vers la VM locale (port 2222)

just publish   # upload vers S3, import du snapshot, enregistrement de l'AMI
```

`publish` nécessite : `just build` terminé, `AMI_BUCKET` défini dans le Justfile,
et AWS CLI configuré.

Le flux de publication complet :
1. Upload de l'image raw vers `s3://AMI_BUCKET/AMI_NAME.img`
2. Import comme snapshot EC2 (`aws ec2 import-snapshot`)
3. Attente jusqu'à la fin de l'import
4. Enregistrement du snapshot comme AMI (`aws ec2 register-image`)

## image.nix

Même override GRUB/BIOS que `local-vm/qcow2.nix`. Le builder `make-single-disk-zfs-image.nix`
crée un layout de partition BIOS ; GRUB est forcé pour le build. L'AMI enregistrée démarre
correctement car GRUB utilise les UUIDs de partition, pas les noms de périphériques.

L'image est construite au format `raw` (pas qcow2) — `aws ec2 import-snapshot` nécessite
une image disque brute.

## Voir aussi

- [Forge — Layouts](/stc/fr/forge/layouts/) — le layout disque `zfs-local-vm`
- [cogitator-hardening](/stc/fr/cogitator/hardening/) — le profil de durcissement utilisé ici
- [relics-impermanence](/stc/fr/relics/impermanence/) — comment fonctionne le rollback
