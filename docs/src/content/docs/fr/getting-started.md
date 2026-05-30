---
title: Premiers pas
description: Comment consommer STC dans ton propre flake Nix.
---

## VM locale en 5 minutes

Clone la schematic `local-vm` et démarre une VM :

```bash
git clone https://github.com/gfriloux/stc.git
cd stc/schematics/local-vm
just build    # construit l'image qcow2 (~5-10 min la première fois)
just run      # boot dans QEMU/KVM
just ssh      # SSH en admin sur le port 2222 (mot de passe: changeme)
```

Prérequis : Nix avec flakes activées, hôte avec KVM (`/dev/kvm` accessible). C'est tout — qemu est fourni par la recette `run`.

## Tu veux un serveur AWS ?

Utilise la schematic `aws-ami` :

```bash
cd stc/schematics/aws-ami
just build    # construit l'AMI
just publish  # publie sur AWS
```

Voir [aws-ami](/fr/schematics/aws-ami/) pour les détails de configuration.

## Tu veux intégrer des modules dans ton flake existant ?

Ajoute STC comme input dans ton `flake.nix` :

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stc = {
      url = "github:gfriloux/stc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### Utiliser un module NixOS

```nix
outputs = { nixpkgs, stc, ... }: {
  nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      stc.nixosModules.relics-networking
      stc.nixosModules.cogitator-hardening
      ./configuration.nix
    ];
  };
};
```

Puis dans `configuration.nix` :

```nix
{
  stc.networking.enable = true;
  stc.networking.nameservers = [ "9.9.9.9" "149.112.112.112" ];

  stc.hardening.enable = true;
}
```

Rien n'est actif tant que tu ne poses pas `enable = true`.

### Utiliser un module Home Manager

```nix
outputs = { nixpkgs, stc, home-manager, ... }: {
  homeConfigurations."alice@workstation" = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      stc.homeModules.cogitator-enginseer
      stc.homeModules.relics-kitty
      ./home.nix
    ];
  };
};
```

Puis dans `home.nix` :

```nix
{
  stc.cogitator.enginseer.enable = true;
  stc.gui.kitty.enable = true;
  stc.gui.kitty.fonts.enable = true;
}
```

### Utiliser un dev shell

```nix
outputs = { stc, ... }: {
  devShells.x86_64-linux.default = stc.devShells.x86_64-linux.ansible;
};
```

Ou avec flake-parts :

```nix
perSystem = { system, ... }: {
  devShells.default = stc.devShells.${system}.ansible;
};
```

Shells disponibles : `ansible`, `terraform`, `mdbook`, `mkdocs`, `zensical`, `vm`, `nixos`.

### Initialiser un template

```bash
mkdir mes-playbooks && cd mes-playbooks
nix flake init -t github:gfriloux/stc#ansible
```

Templates disponibles : `ansible`, `terraform`, `mdbook`, `mkdocs`, `zensical`.

## Ce qui est disponible

| Catégorie | Référence |
|-----------|-----------|
| Modules NixOS (reliques) | [Reliques](/fr/relics/) |
| Modules NixOS (profils) | [Cogitator](/fr/cogitator/) |
| Modules Home Manager | [Reliques — Apps graphiques](/fr/relics/home-apps/), [Cogitator — Enginseer](/fr/cogitator/enginseer/) |
| Dev shells | [Forge — Shells](/fr/forge/shells/) |
| Templates de flake | [Forge — Templates](/fr/forge/templates/) |
| Layouts de disque | [Forge — Layouts](/fr/forge/layouts/) |
| Exemples complets | [Schematics](/fr/schematics/) |
