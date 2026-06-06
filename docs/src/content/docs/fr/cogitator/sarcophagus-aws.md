---
title: Profil Sarcophagus AWS
description: cogitator-sarcophagus-aws — image disque NixOS pour AMI AWS avec ZFS, impermanence et durcissement.
---

**Module :** `stc.nixosModules.cogitator-sarcophagus-aws`

Le Sarcophagus est le caisson hermétique qui préserve les restes d'un Space Marine mortellement blessé. Ce cogitator scelle ton système dans une image disque brute gravée de ZFS, impermanence et durcissement : le sarcophage inerte, préservant l'essence de ta configuration en attente de déploiement sur les champs de bataille AWS. Une fois importé comme AMI et éveillé dans une instance EC2, ce sarcophage devient le noyau vivant du Dreadnought complet.

Construit une image disque NixOS brute (raw) importable comme AMI AWS, avec ZFS,
impermanence et durcissement complet. Inclut la relique de plateforme AWS (pilotes
NVMe/ENA, NTP, console série, expansion du pool EBS) et intègre le schéma disque
et le constructeur d'image — aucun import `disko` externe n'est nécessaire.

Les instances déployées depuis cette AMI sont destinées à être gérées avec
[cogitator-dreadnought](/stc/fr/cogitator/dreadnought/).

## Ce qu'il compose

| Composant | Rôle |
|-----------|------|
| `relics-zfs` | Noyau compatible ZFS, scrub automatique, TRIM, ZED |
| `relics-networking` | DHCP, DNS Quad9 |
| `relics-impermanence` | Rollback du root vers `@blank` à chaque démarrage |
| `relics-aws` | Pilotes NVMe/ENA, NTP, console série, expansion pool EBS |
| `cogitator-hardening` | Durcissement noyau + réseau + système de fichiers + SSH |
| Schéma disko | GPT sur `/dev/vda` — 1 Gio FAT32 `/boot` + pool ZFS |
| Override GRUB | BIOS/GRUB requis par `make-single-disk-zfs-image.nix` |
| `system.build.awsImage` | Constructeur d'image brute |

`disko.nixosModules.disko` et `impermanence.nixosModules.impermanence` sont
injectés automatiquement — le consommateur n'a pas besoin de les importer.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.sarcophagus-aws.enable` | bool | `false` | Active ce cogitator |
| `stc.cogitator.sarcophagus-aws.poolName` | str | `"vmpool"` | Nom du pool ZFS |
| `stc.cogitator.sarcophagus-aws.rootSize` | int | `4096` | Taille de l'image disque en Mio |
| `stc.cogitator.sarcophagus-aws.memSize` | int | `4096` | Mémoire de la VM de construction en Mio |
| `stc.cogitator.sarcophagus-aws.ebsDisk` | str | `"nvme0n1"` | Nom du périphérique EBS (sans `/dev/`). Utiliser `xvda` pour les instances Xen. |
| `stc.cogitator.sarcophagus-aws.ebsPartition` | int | `3` | Numéro de partition contenant le pool ZFS sur le disque EBS |
| `stc.cogitator.sarcophagus-aws.impermanence.extraDirectories` | list de str | `[]` | Répertoires supplémentaires à persister |
| `stc.cogitator.sarcophagus-aws.impermanence.extraFiles` | list de str | `[]` | Fichiers supplémentaires à persister |

## Exemple d'utilisation

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    stc = {
      url = "github:gfriloux/stc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, stc, ... }: {
    nixosConfigurations.mon-ami = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-sarcophagus-aws
        ({ ... }: {
          stc.cogitator.sarcophagus-aws = {
            enable = true;
            impermanence.extraDirectories = [ "/var/db/sudo/lectured" ];
          };
          networking.hostName = "mon-ami";
          networking.hostId = "cafebabe"; # à remplacer — doit être unique
          users = {
            mutableUsers = false;
            users.admin = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... toi@hote" ];
            };
          };
          security.sudo.wheelNeedsPassword = false;
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

Construire et publier :

```bash
nix build .#nixosConfigurations.mon-ami.config.system.build.awsImage
# result/nixos.root.img est l'image brute à importer comme snapshot AWS
```

:::caution[Clé SSH obligatoire]
`cogitator-hardening` désactive l'authentification SSH par mot de passe. Ajoute
ta clé publique dans `openssh.authorizedKeys.keys` avant de construire — sans ça,
tu ne pourras pas te connecter à l'instance.
:::

:::caution[Changer le hostId]
`networking.hostId = "cafebabe"` est un placeholder. Chaque hôte ZFS doit avoir
un hostId unique. Génères-en un : `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
:::

## Schéma disque

```
/dev/vda (GPT)
├── partition 1 — 1 Gio  FAT32  /boot   (label: ESP)
└── partition 2 — 100%   Pool ZFS (vmpool par défaut)
    ├── vmpool/root    →  /        éphémère — rollback vers @blank à chaque boot
    ├── vmpool/nix     →  /nix     persistant — le store Nix
    └── vmpool/persist →  /persist persistant — état explicite uniquement
```

Au démarrage sur EC2, `relics-aws` exécute `growpart` + `zpool online -e` pour
étendre le pool ZFS à la taille totale du volume EBS.

## Voir aussi

- [Schéma aws-ami](/stc/fr/schematics/aws-ami/) — exemple prêt à l'emploi basé sur ce cogitator
- [cogitator-dreadnought](/stc/fr/cogitator/dreadnought/) — profil pour les instances déployées depuis cette AMI
- [relics-aws](/stc/fr/relics/aws/) — la relique de plateforme AWS
- [relics-impermanence](/stc/fr/relics/impermanence/) — fonctionnement du rollback root
- [cogitator-sarcophagus-kvm](/stc/fr/cogitator/sarcophagus-kvm/) — la variante KVM
