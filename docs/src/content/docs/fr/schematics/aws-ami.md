---
title: aws-ami
description: Une AMI NixOS pour AWS EC2 avec ZFS, impermanence et durcissement.
---

**Source :** `schematics/aws-ami/`

Une image AMI NixOS pour AWS EC2, avec stockage ZFS, impermanence et durcissement complet.

Ce schématic utilise [cogitator-sarcophagus-aws](/stc/fr/cogitator/sarcophagus-aws/),
qui intègre le schéma disque, la configuration de plateforme AWS, l'override GRUB et
le constructeur d'image brute — aucun import `disko` séparé ni module `image.nix`
n'est nécessaire.

Les instances déployées depuis cette AMI sont destinées à être gérées avec
[cogitator-dreadnought](/stc/fr/cogitator/dreadnought/).

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
| `stc.nixosModules.cogitator-sarcophagus-aws` | ZFS + impermanence + durcissement + plateforme AWS + schéma disque + constructeur d'image brute |

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

## flake.nix complet

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    stc = {
      url = "github:gfriloux/stc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, stc, ... }: {
    nixosConfigurations.aws-ami = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-sarcophagus-aws
        ({ ... }: {
          stc.cogitator.sarcophagus-aws = {
            enable = true;
            impermanence.extraDirectories = [ "/var/db/sudo/lectured" ];
          };
          networking.hostName = "aws-ami";
          networking.hostId = "cafebabe";  # remplace par le tien
          users = {
            mutableUsers = false;
            users.root.initialPassword = "changeme";
            users.admin = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              initialPassword = "changeme";
              openssh.authorizedKeys.keys = [
                # "ssh-ed25519 AAAA... toi@hote"
              ];
            };
          };
          security.sudo.wheelNeedsPassword = false;
          time.timeZone = "UTC";
          i18n.defaultLocale = "en_US.UTF-8";
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

:::caution[Changer le hostId]
`networking.hostId = "cafebabe"` est un placeholder. Chaque machine ZFS doit avoir
un hostId unique. Génère-en un : `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
:::

## Voir aussi

- [cogitator-sarcophagus-aws](/stc/fr/cogitator/sarcophagus-aws/) — référence complète des options du constructeur d'image
- [cogitator-dreadnought](/stc/fr/cogitator/dreadnought/) — profil pour gérer les instances déployées depuis cette AMI
- [relics-aws](/stc/fr/relics/aws/) — la relique de plateforme AWS
- [relics-impermanence](/stc/fr/relics/impermanence/) — comment fonctionne le rollback
