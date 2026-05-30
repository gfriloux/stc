---
title: local-vm
description: Une VM de développement NixOS QEMU/KVM avec ZFS, impermanence et durcissement complet.
---

**Source :** `schematics/local-vm/`

Une machine virtuelle QEMU/KVM locale exécutant NixOS avec stockage ZFS, impermanence
(la racine revient à `@blank` à chaque démarrage), et durcissement complet. Utilise
ceci comme VM de développement ou de staging.

## Prérequis

- Nix avec les flakes activés
- Hôte capable de KVM (`/dev/kvm` accessible)
- qemu n'est pas nécessaire sur l'hôte — la recette `just run` le fournit via `nix shell`

## Modules utilisés

| Module | Objet |
|--------|-------|
| `disko.nixosModules.disko` | Partitionnement déclaratif du disque |
| `stc.nixosModules.relics-boot` | systemd-boot + EFI |
| `stc.nixosModules.relics-zfs` | Noyau ZFS compatible, scrub auto, TRIM, ZED |
| `stc.nixosModules.relics-networking` | DHCP, DNS Quad9 |
| `stc.nixosModules.relics-impermanence` | Rollback racine à chaque démarrage |
| `stc.nixosModules.cogitator-hardening` | Suite de durcissement complète |
| `stc.nixosModules.cogitator-vm` | fish, SSH, utilisateur admin, Docker optionnel, GC Nix |
| `stc.lib.layouts.zfs-local-vm` | Layout disque EFI + ZFS |
| `./qcow2.nix` | Builder d'image qcow2 (override GRUB pour le build) |

## Configuration QEMU critique

Deux paramètres sont obligatoires pour les VMs QEMU basées sur virtio :

```nix
# Les drivers virtio doivent être chargés dans l'initrd pour que /dev/vda existe
# avant que ZFS ne tente d'importer le pool.
boot.initrd.kernelModules = [ "virtio_pci" "virtio_blk" ];

# Les disques virtio QEMU n'ont pas d'entrées /dev/disk/by-id/.
# ZFS cherche là par défaut — redirige-le vers /dev.
boot.zfs.devNodes = "/dev";
```

Sans `virtio_pci` et `virtio_blk` dans l'initrd, le disque est invisible quand ZFS
tente d'importer le pool et la VM ne démarrera pas. Sans `devNodes = "/dev"`, ZFS
ne trouvera pas le pool par le chemin de périphérique attendu.

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
    disko.follows = "stc/disko";
  };

  outputs = { nixpkgs, stc, disko, ... }: {
    nixosConfigurations.local-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        stc.nixosModules.relics-boot
        stc.nixosModules.relics-zfs
        stc.nixosModules.relics-networking
        stc.nixosModules.relics-impermanence
        stc.nixosModules.cogitator-hardening
        stc.nixosModules.cogitator-vm
        (stc.lib.layouts.zfs-local-vm { poolName = "vmpool"; })
        ./qcow2.nix
        ({ ... }: {
          stc = {
            boot.enable = true;
            zfs.enable = true;
            networking.enable = true;
            hardening.enable = true;
            impermanence = {
              enable = true;
              poolName = "vmpool";
              extraDirectories = [ "/var/db/sudo/lectured" ];
            };
            cogitator.vm = {
              enable = true;
              username = "admin";
              authorizedKeys = [
                # "ssh-ed25519 AAAA... you@host"
              ];
              docker.enable = false;
            };
          };

          boot.initrd.kernelModules = [ "virtio_pci" "virtio_blk" ];
          boot.zfs.devNodes = "/dev";

          networking.hostName = "local-vm";
          networking.hostId = "deadc0de";  # remplace par le tien

          users.mutableUsers = false;
          users.users.admin.initialPassword = "changeme";
          users.users.root.initialPassword = "changeme";
          security.sudo.wheelNeedsPassword = false;

          time.timeZone = "UTC";
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

## qcow2.nix

Le module `qcow2.nix` surcharge le chargeur de démarrage pour le build de l'image.
Le builder NixOS `make-single-disk-zfs-image.nix` utilise un layout de partition BIOS,
et systemd-boot refuse de s'installer là. GRUB est forcé uniquement pour le build de
l'image ; le système live utilise toujours systemd-boot.

## Voir aussi

- [Forge — Layouts](/fr/forge/layouts/) — le layout disque `zfs-local-vm`
- [relics-impermanence](/fr/relics/impermanence/) — comment fonctionne le rollback
- [cogitator-vm](/fr/cogitator/vm/) — les options du profil VM de base
