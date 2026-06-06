---
title: local-vm
description: Une VM de développement NixOS QEMU/KVM avec ZFS, impermanence et durcissement complet.
---

**Source :** `schematics/local-vm/`

Une machine virtuelle QEMU/KVM locale exécutant NixOS avec stockage ZFS, impermanence
(la racine revient à `@blank` à chaque démarrage), et durcissement complet. Utilise
ceci comme VM de développement ou de staging.

Ce schématic utilise [cogitator-sarcophagus-kvm](/stc/fr/cogitator/sarcophagus-kvm/),
qui intègre le schéma disque, l'override GRUB et le constructeur qcow2 — aucun import
`disko` séparé ni module `qcow2.nix` n'est nécessaire.

## Prérequis

- Nix avec les flakes activés
- Hôte capable de KVM (`/dev/kvm` accessible)
- qemu n'est pas nécessaire sur l'hôte — la recette `just run` le fournit via `nix shell`

## Modules utilisés

| Module | Objet |
|--------|-------|
| `stc.nixosModules.cogitator-sarcophagus-kvm` | ZFS + impermanence + durcissement + schéma disque + constructeur qcow2 |
| `stc.nixosModules.cogitator-vm` | fish, SSH, utilisateur admin, Docker optionnel, GC Nix |

## Recettes du Justfile

### VM complète avec ZFS

```bash
just build    # construit l'image qcow2 (~5-10 minutes la première fois)
just run      # la démarre avec QEMU/KVM, SSH sur le port 2222
just ssh      # SSH dans la VM en cours d'exécution en tant qu'admin
```

`run` utilise `snapshot=on` — l'image du store Nix est gardée en lecture seule et chaque
démarrage part de la même base. Tes changements sur `/persist` survivent car ils sont sur
le dataset persistant, mais rien d'autre ne le fait.

### Recettes de développement

```bash
just fmt          # formatage alejandra
just fmt-check    # vérification sans modification
just lint         # statix + deadnix
just ci           # fmt-check + lint
just check        # nix flake check --show-trace
```

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
    nixosConfigurations.local-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-sarcophagus-kvm
        stc.nixosModules.cogitator-vm
        ({ ... }: {
          stc.cogitator.sarcophagus-kvm = {
            enable = true;
            impermanence.extraDirectories = [ "/var/db/sudo/lectured" ];
          };
          stc.cogitator.vm = {
            enable = true;
            username = "admin";
            authorizedKeys = [
              # "ssh-ed25519 AAAA... toi@hote"
            ];
            docker.enable = false;
          };
          networking.hostName = "local-vm";
          networking.hostId = "deadc0de";  # remplace par le tien
          users.mutableUsers = false;
          users.users.admin.initialPassword = "changeme";
          users.users.root.initialPassword = "changeme";
          security.sudo.wheelNeedsPassword = false;
          time.timeZone = "UTC";
          i18n.defaultLocale = "fr_FR.UTF-8";
          console.keyMap = "fr";
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

:::caution[Changer le hostId]
`networking.hostId = "deadc0de"` est un placeholder. Chaque machine ZFS doit avoir
un hostId unique. Génère-en un : `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
:::

:::caution[Changer les mots de passe]
`initialPassword = "changeme"` est livré avec `mutableUsers = false` : le mot de
passe ne pourra jamais être changé avec `passwd` — il reste `changeme`. Remplace-le
par un vrai `hashedPassword` (ex. `mkpasswd -m sha-512`) avant de builder autre chose
qu'une VM jetable. Le build émet des warnings tant que ces placeholders sont en place.
:::

## Voir aussi

- [cogitator-sarcophagus-kvm](/stc/fr/cogitator/sarcophagus-kvm/) — référence complète des options du constructeur d'image
- [relics-impermanence](/stc/fr/relics/impermanence/) — comment fonctionne le rollback
- [cogitator-vm](/stc/fr/cogitator/vm/) — les options du profil VM de base
