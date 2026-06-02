---
title: Profil Sarcophagus KVM
description: cogitator-sarcophagus-kvm — image disque NixOS QEMU/KVM avec ZFS, impermanence et durcissement.
---

**Module :** `stc.nixosModules.cogitator-sarcophagus-kvm`

Le Sarcophagus est le caisson de maintien en vie artificielle intégré au châssis d'un Dreadnought, préservant le Space Marine mortellement blessé en stase entre les batailles. Ce cogitator NixOS scelle ta configuration dans une image qcow2 scellée et immuable — une chambre hermétiquement préservée en attente de déploiement sur tout hyperviseur KVM. L'image est le Sarcophagus : le caisson scellé de l'essence de ton système avant qu'il ne s'éveille sur le champ de bataille.

Construit une image disque NixOS (qcow2) prête à démarrer sur tout hyperviseur KVM.
Compose ZFS, réseau, impermanence et la suite complète de durcissement, et intègre
le schéma disque et le constructeur d'image — aucun import `disko` externe n'est nécessaire.

## Ce qu'il compose

| Composant | Rôle |
|-----------|------|
| `relics-zfs` | Noyau compatible ZFS, scrub automatique, TRIM, ZED |
| `relics-networking` | DHCP, DNS Quad9 |
| `relics-impermanence` | Rollback du root vers `@blank` à chaque démarrage |
| `cogitator-hardening` | Durcissement noyau + réseau + système de fichiers + SSH |
| Schéma disko | GPT sur `/dev/vda` — 1 Gio FAT32 `/boot` + pool ZFS |
| Override GRUB | BIOS/GRUB requis par `make-single-disk-zfs-image.nix` |
| `system.build.qcow2` | Constructeur d'image qcow2 |

`disko.nixosModules.disko` et `impermanence.nixosModules.impermanence` sont
injectés automatiquement — le consommateur n'a pas besoin de les importer.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.sarcophagus-kvm.enable` | bool | `false` | Active ce cogitator |
| `stc.cogitator.sarcophagus-kvm.poolName` | str | `"vmpool"` | Nom du pool ZFS |
| `stc.cogitator.sarcophagus-kvm.rootSize` | int | `20480` | Taille de l'image disque en Mio |
| `stc.cogitator.sarcophagus-kvm.memSize` | int | `4096` | Mémoire de la VM de construction en Mio |
| `stc.cogitator.sarcophagus-kvm.impermanence.extraDirectories` | list de str | `[]` | Répertoires supplémentaires à persister sous `/persist` |
| `stc.cogitator.sarcophagus-kvm.impermanence.extraFiles` | list de str | `[]` | Fichiers supplémentaires à persister sous `/persist` |

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
    nixosConfigurations.ma-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-sarcophagus-kvm
        stc.nixosModules.cogitator-vm   # optionnel : fish, SSH, utilisateur admin
        ({ ... }: {
          stc.cogitator.sarcophagus-kvm = {
            enable = true;
            impermanence.extraDirectories = [ "/var/db/sudo/lectured" ];
          };
          stc.cogitator.vm = {
            enable = true;
            username = "admin";
            authorizedKeys = [ "ssh-ed25519 AAAA... toi@hote" ];
          };
          networking.hostName = "ma-vm";
          networking.hostId = "deadc0de"; # à remplacer — doit être unique
          users.mutableUsers = false;
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

Construire l'image :

```bash
nix build .#nixosConfigurations.ma-vm.config.system.build.qcow2
qemu-system-x86_64 -enable-kvm -m 4096 -drive file=result,format=qcow2
```

:::caution[Changer le hostId]
`networking.hostId = "deadc0de"` est un placeholder. Chaque hôte ZFS doit avoir
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

## Voir aussi

- [Schéma local-vm](/stc/fr/schematics/local-vm/) — exemple prêt à l'emploi basé sur ce cogitator
- [relics-impermanence](/stc/fr/relics/impermanence/) — fonctionnement du rollback root
- [cogitator-hardening](/stc/fr/cogitator/hardening/) — la suite de durcissement composée
- [cogitator-sarcophagus-aws](/stc/fr/cogitator/sarcophagus-aws/) — la variante AWS
