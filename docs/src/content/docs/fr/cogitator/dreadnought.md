---
title: Profil Dreadnought
description: cogitator-dreadnought — profil système en exploitation pour instances EC2 déployées depuis une AMI sarcophagus-aws.
---

**Module :** `stc.nixosModules.cogitator-dreadnought`

Un Dreadnought est un walker blindé abritant un Space Marine vénéré mais mortellement blessé — l'Ancient éveillé du Sarcophagus et jeté au combat, fusionnant chair et machine, mémoire et acier. Ce cogitator est le rite d'éveil : il prend une AMI (le Sarcophagus scellé) et la ressuscite en instance EC2 en cours d'exécution (le Dreadnought). L'instance est maintenant opérationnelle, armée et liée au substrat durci de ton infrastructure, attendant ses ordres sur le champ de bataille.

Profil d'exploitation pour les instances EC2 NixOS déployées depuis une AMI
[sarcophagus-aws](/stc/fr/cogitator/sarcophagus-aws/). Active ZFS, réseau,
impermanence, support de la plateforme AWS et la suite complète de durcissement
sur le système en cours d'exécution.

Aucun schéma disque ni constructeur d'image n'est inclus — l'AMI a déjà
partitionné le disque. Le layout ZFS des systèmes de fichiers et la configuration
GRUB sont pris en charge par ce cogitator (dérivés de `poolName` et `ebsDisk`),
donc le `hardware-configuration.nix` du consommateur n'a besoin que des modules
noyau spécifiques à l'instance générés par `nixos-generate-config`.

Ajoute d'autres cogitators par-dessus (`cogitator-docker-server`, `cogitator-vm`,
etc.) pour construire le profil de services dont tu as besoin.

## Ce qu'il compose

| Composant | Rôle |
|-----------|------|
| `relics-zfs` | Noyau compatible ZFS, scrub automatique, TRIM, ZED |
| `relics-networking` | DHCP, DNS Quad9 |
| `relics-impermanence` | Rollback du root vers `@blank` à chaque démarrage |
| `relics-aws` | Pilotes NVMe/ENA, NTP, console série, expansion pool EBS |
| `cogitator-hardening` | Durcissement noyau + réseau + système de fichiers + SSH |

`impermanence.nixosModules.impermanence` est injecté automatiquement.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.dreadnought.enable` | bool | `false` | Active ce cogitator |
| `stc.cogitator.dreadnought.poolName` | str | `"vmpool"` | Nom du pool ZFS — doit correspondre au pool créé par sarcophagus-aws |
| `stc.cogitator.dreadnought.ebsDisk` | str | `"nvme0n1"` | Nom du périphérique EBS (sans `/dev/`). Utiliser `xvda` pour les instances Xen. |
| `stc.cogitator.dreadnought.ebsPartition` | int | `3` | Numéro de partition contenant le pool ZFS sur le disque EBS |
| `stc.cogitator.dreadnought.impermanence.extraDirectories` | list de str | `[]` | Répertoires supplémentaires à persister sous `/persist` |
| `stc.cogitator.dreadnought.impermanence.extraFiles` | list de str | `[]` | Fichiers supplémentaires à persister sous `/persist` |

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
    nixosConfigurations.mon-serveur = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-dreadnought

        # Ajouter des profils de services par-dessus
        stc.nixosModules.cogitator-docker-server  # exemple

        # Configuration matérielle générée depuis l'instance en cours d'exécution
        ./hardware-configuration.nix

        ({ ... }: {
          stc.cogitator.dreadnought = {
            enable = true;
            poolName = "vmpool"; # doit correspondre au nom de pool de l'AMI
            impermanence.extraDirectories = [
              "/var/db/sudo/lectured"
              "/var/lib/docker"
            ];
          };
          # stc.cogitator.docker-server.enable = true; # si ce cogitator est utilisé

          networking.hostName = "mon-serveur";
          networking.hostId = "abcd1234"; # doit correspondre à la valeur définie dans l'AMI
          users.mutableUsers = false;
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

## Configuration matérielle

Le layout des systèmes de fichiers et le chargeur de démarrage GRUB sont
entièrement gérés par ce cogitator. Le `hardware-configuration.nix` du
consommateur n'a besoin que de la section modules noyau — lance sur l'instance
en cours d'exécution :

```bash
nixos-generate-config --show-hardware-config
```

Copie uniquement les lignes `boot.initrd.availableKernelModules` et
`boot.kernelModules` dans ton `hardware-configuration.nix`. Les déclarations
de systèmes de fichiers et le périphérique de démarrage sont déjà définis
par le cogitator et n'ont pas besoin d'être répétés.

## Voir aussi

- [cogitator-sarcophagus-aws](/stc/fr/cogitator/sarcophagus-aws/) — construit l'AMI sur laquelle ce profil s'exécute
- [relics-aws](/stc/fr/relics/aws/) — la relique de plateforme AWS
- [relics-impermanence](/stc/fr/relics/impermanence/) — fonctionnement du rollback root
- [cogitator-hardening](/stc/fr/cogitator/hardening/) — la suite de durcissement composée
