---
title: Profil VM
description: cogitator-vm — base opinionée pour les VMs NixOS de développement et de staging.
---

**Module :** `stc.nixosModules.cogitator-vm`

Une base opinionée pour une machine virtuelle NixOS de développement ou de staging :
shell fish, SSH, un utilisateur principal avec accès wheel, Docker optionnel, et GC Nix
automatique pour garder le store sous contrôle.

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
| `stc.cogitator.vm.nix.gc.enable` | bool | `true` | Active le garbage collection Nix automatique |
| `stc.cogitator.vm.nix.gc.dates` | string | `"weekly"` | Quand exécuter le GC Nix (expression de calendrier systemd) |
| `stc.cogitator.vm.nix.gc.keepDays` | int | `5` | Supprimer les chemins du store Nix plus anciens que ce nombre de jours |

## Ce qu'il fait

Lorsqu'il est activé :

- Active les fonctionnalités expérimentales `nix-command` et `flakes`
- Active `nix.optimise.automatic` (déduplication)
- Configure le GC Nix si `nix.gc.enable = true`
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
    nix.gc = {
      enable = true;
      dates = "weekly";
      keepDays = 7;
    };
  };

  stc.cogitator.hardening.enable = true;
  stc.relics.hardening.network.allowedTCPPorts = [ 22 ];

  networking.hostName = "dev-vm";
  networking.hostId = "a1b2c3d4";

  system.stateVersion = "24.11";
}
```

## Voir aussi

- [cogitator-hardening](/stc/fr/cogitator/hardening/) — à combiner pour une VM durcie
- [cogitator-enginseer](/stc/fr/cogitator/enginseer/) — à combiner pour le kit CLI complet
- [Schématic : local-vm](/stc/fr/schematics/local-vm/) — exemple complet et fonctionnel
