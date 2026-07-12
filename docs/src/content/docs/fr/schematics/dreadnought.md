---
title: dreadnought
description: Une instance EC2 NixOS déployée depuis une AMI sarcophagus-aws, gérée via deploy-rs.
---

**Source :** `schematics/dreadnought/`

Une configuration système NixOS pour une instance EC2 lancée depuis une AMI
[sarcophagus-aws](/stc/fr/schematics/aws-ami/), déployée et gérée via
[deploy-rs](https://github.com/serokell/deploy-rs).

Ce schématic ne construit pas d'image disque — il construit une closure système
NixOS et la déploie sur une instance en cours d'exécution. Le disque a déjà été
partitionné par l'AMI sarcophagus-aws.

## Prérequis

- Une instance EC2 exécutant une AMI NixOS construite avec `cogitator-sarcophagus-aws`
- Nix avec les flakes activés sur la machine de build
- `deploy-rs` disponible (fourni par le devShell du schématic)
- Accès SSH depuis ta machine de build vers l'instance EC2 (port 22, en tant qu'`admin`)

## Configuration

### 1. Récupérer les modules noyau

SSH dans l'instance EC2 en cours d'exécution et lance :

```bash
nixos-generate-config --show-hardware-config
```

Copie uniquement les lignes `boot.initrd.availableKernelModules` et
`boot.kernelModules` dans `hardware-configuration.nix`. Le layout ZFS
(systèmes de fichiers, GRUB) est déjà pris en charge par `cogitator-dreadnought`
et ne doit pas être répété.

### 2. Définir le hostname

Dans `flake.nix`, mets à jour `deploy.nodes.dreadnought.hostname` et la variable
`HOST` du Justfile avec l'IP publique ou le nom DNS de ton instance.

### 3. Faire correspondre les valeurs de l'AMI

Les éléments suivants doivent correspondre aux valeurs utilisées lors de la construction
de l'AMI sarcophagus-aws :

- `networking.hostId` — copie depuis le `flake.nix` de l'AMI
- `stc.cogitator.dreadnought.poolName` — par défaut `"vmpool"` sauf si surchargé

### 4. Ajouter ta clé SSH

Ajoute ta clé publique dans `users.users.admin.openssh.authorizedKeys.keys`.

:::danger[Ne pas déployer tel quel]
Cette schématique livre `users.allowNoPasswordLogin = true` (uniquement pour
qu'elle s'évalue avant que tu ajoutes une clé), `security.sudo.wheelNeedsPassword = false`
(sudo sans mot de passe pour wheel) et un `networking.hostId = "cafebabe"` factice.
Après avoir ajouté ta clé SSH, passe `allowNoPasswordLogin = false` et remplace le
hostId. Avec SSH par clé uniquement et sudo sans mot de passe, quiconque détient la
clé de `admin` a un accès root direct — fais-en un choix délibéré.
:::

## Modules utilisés

| Module | Objet |
|--------|-------|
| `stc.nixosModules.cogitator-dreadnought` | ZFS + impermanence + durcissement + plateforme AWS + layout ZFS + GRUB |
| `./hardware-configuration.nix` | Modules noyau spécifiques à l'instance EC2 |

## Recettes du Justfile

```bash
just build    # construit la closure système (ne déploie pas)
just deploy   # déploie sur l'instance EC2 via deploy-rs
just ssh      # SSH dans l'instance
just check    # nix flake check (inclut les vérifications de schéma deploy-rs)

just fmt      # formatage alejandra
just ci       # fmt-check + lint
just update   # met à jour les inputs du flake
```

## Ajout de profils de services

Décommente et configure des cogitators supplémentaires dans `flake.nix` :

```nix
modules = [
  stc.nixosModules.cogitator-dreadnought
  stc.nixosModules.cogitator-docker-server  # Traefik + CrowdSec + optional notifications
  stc.nixosModules.cogitator-vm             # fish, SSH, utilisateur admin
  ./hardware-configuration.nix
  ({ ... }: {
    stc.cogitator.dreadnought.enable = true;
    stc.cogitator.docker-server.enable = true;
    stc.cogitator.vm = { enable = true; username = "admin"; authorizedKeys = [ ... ]; };
    # ...
  })
];
```

## Configuration deploy-rs

Le schématic câble deploy-rs avec `sshUser = "admin"` et `user = "root"`.
deploy-rs se connecte en SSH en tant qu'`admin` et utilise `sudo` pour basculer
le profil système en tant que root.

La sortie `checks` intègre la validation du schéma deploy-rs dans `nix flake check`,
ce qui permet de détecter les erreurs de configuration avant le déploiement.

## Voir aussi

- [cogitator-dreadnought](/stc/fr/cogitator/dreadnought/) — référence complète des options
- [Schématic aws-ami](/stc/fr/schematics/aws-ami/) — construit l'AMI sur laquelle ceci s'exécute
- [cogitator-sarcophagus-aws](/stc/fr/cogitator/sarcophagus-aws/) — le cogitator constructeur d'AMI
