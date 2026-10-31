---
title: Profil VM
description: cogitator-vm — base opinionée pour les VMs NixOS de développement et de staging.
---

**Module :** `stc.nixosModules.cogitator-vm`

Une base opinionée pour une machine virtuelle NixOS de développement ou de staging :
shell fish, SSH, un utilisateur principal avec accès wheel, Docker optionnel, et un store
Nix et un journal bornés par l'[entretien de Nix](/stc/fr/relics/nix-housekeeping/),
avec une fenêtre de GC de 5 jours.

Compose avec `cogitator-hardening` et `cogitator-enginseer` pour une VM de développement
complète.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.vm.enable` | bool | `false` | Active le profil VM de base STC |
| `stc.cogitator.vm.username` | string | `"admin"` | Compte utilisateur principal créé sur la VM |
| `stc.cogitator.vm.authorizedKeys` | liste de strings | `[]` | Clés SSH autorisées pour l'utilisateur principal |
| `stc.cogitator.vm.linger` | bool | `true` | Garde l'instance systemd/les services de l'utilisateur actifs sans session ouverte. Mettre à `false` sur un hôte durci. |
| `stc.cogitator.vm.docker.enable` | bool | `false` | Active Docker et ajoute l'utilisateur principal au groupe docker (≈ root — opt-in) |

## Ce qu'il fait

Lorsqu'il est activé :

- Active les fonctionnalités expérimentales `nix-command` et `flakes`
- Active l'[entretien de Nix](/stc/fr/relics/nix-housekeeping/) (`mkDefault`) avec
  `gc.keepDays = 5` (`mkDefault`) : GC hebdomadaire, GC sous pression disque,
  déduplication hebdomadaire, builds qui cèdent, journal plafonné
- Active `programs.fish`
- Crée un utilisateur (`username`) avec :
  - `isNormalUser = true`
  - `extraGroups = [ "wheel" ]` (+ `"docker"` si `docker.enable = true`)
  - `shell = pkgs.fish`
  - `linger = cfg.linger` (défaut : `true`)
  - Clés SSH autorisées depuis `authorizedKeys`
- Active `services.openssh`
- Si `docker.enable = true` : active `virtualisation.docker` et installe `docker-compose`

:::caution[Groupe docker ≈ root, et sudo avec SSH par clé]
`docker.enable` est désactivé par défaut : ajouter l'utilisateur au groupe
`docker` équivaut à un accès root, donc c'est opt-in plutôt qu'un défaut
silencieux.

L'utilisateur est créé avec SSH par clé uniquement et **sans mot de passe**,
donc `sudo` est inutilisable tel quel. Si tu as besoin de `sudo`, pose
`security.sudo.wheelNeedsPassword = false` (sans mot de passe — pratique pour
une machine en SSH par clé, mais comprends le trade-off) ou attribue un mot de
passe à l'utilisateur par un autre moyen.

`linger = true` est posé pour que les services utilisateur (et les charges
rootless) continuent de tourner quand l'utilisateur n'est pas connecté.
:::

:::note[Renommées en v0.19.0 : les options de GC]
`stc.cogitator.vm.nix.gc.{enable,dates,keepDays}` ont déménagé vers
`stc.relics.nixHousekeeping.gc.{enable,dates,keepDays}`. Les anciens noms
marchent toujours, avec un avertissement de dépréciation ; une valeur posée là
bat toujours le défaut de 5 jours du profil.

Le profil reçoit aussi le reste de la relique : `min-free` / `max-free`, un
journal plafonné à 500M et un mois, et des builds qui cèdent la place. Chacun a
son propre interrupteur sur la relique.
:::

:::note[Changement cassant]
`docker.enable` valait `true` par défaut auparavant. Si tu comptais sur
l'activation implicite de Docker, pose explicitement
`stc.cogitator.vm.docker.enable = true;`.
:::

## Exemple d'utilisation

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-vm
  stc.nixosModules.cogitator-hardening
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.vm = {
    enable = true;
    username = "alice";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... alice@laptop"
    ];
    docker.enable = true;
  };
  stc.relics.nixHousekeeping.gc.keepDays = 7;

  stc.cogitator.hardening.enable = true;

  networking.hostName = "dev-vm";
  networking.hostId = "a1b2c3d4";

  system.stateVersion = "24.11";
}
```

## Voir aussi

- [cogitator-hardening](/stc/fr/cogitator/hardening/) — à combiner pour une VM durcie
- [cogitator-enginseer](/stc/fr/cogitator/enginseer/) — à combiner pour le kit CLI complet
- [Entretien de Nix](/stc/fr/relics/nix-housekeeping/) — les options de GC et de journal
- [Schématic : local-vm](/stc/fr/schematics/local-vm/) — exemple complet et fonctionnel
