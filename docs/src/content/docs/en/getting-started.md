---
title: Getting Started
description: How to consume STC in your own Nix flake.
---

## Local VM in 5 Minutes

Clone the `local-vm` schematic and boot a VM:

```bash
git clone https://github.com/gfriloux/stc.git
cd stc/schematics/local-vm
just build    # builds the qcow2 image (~5-10 min on first run)
just run      # boots in QEMU/KVM
just ssh      # SSH as admin on port 2222 (password: changeme)
```

:::tip[RITE · MAGOS COUNSEL]
Prerequisites: Nix with flakes enabled and a host with KVM (`/dev/kvm` accessible). That's it — qemu is provided by the `run` recipe.
:::

## Want an AWS Server?

Use the `aws-ami` schematic:

```bash
cd stc/schematics/aws-ami
just build    # builds the AMI
just publish  # publishes to AWS
```

See [aws-ami](/stc/en/schematics/aws-ami/) for configuration details.

## Want to Integrate Modules into Your Existing Flake?

Add STC as an input in your `flake.nix`:

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

:::danger[INTERDICTION · WARNING SEAL]
Never declare system configuration inside STC itself — that is technical heresy. STC is a toolbox: your production flake declares the system, STC provides the building blocks.
:::

### Using a NixOS Module

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

Then in `configuration.nix`:

```nix
{
  stc.networking.enable = true;
  stc.networking.nameservers = [ "9.9.9.9" "149.112.112.112" ];

  stc.hardening.enable = true;
}
```

Nothing is active until you set `enable = true`.

### Using a Home Manager Module

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

Then in `home.nix`:

```nix
{
  stc.cogitator.enginseer.enable = true;
  stc.gui.kitty.enable = true;
  stc.gui.kitty.fonts.enable = true;
}
```

### Using a Dev Shell

```nix
outputs = { stc, ... }: {
  devShells.x86_64-linux.default = stc.devShells.x86_64-linux.ansible;
};
```

Or with flake-parts:

```nix
perSystem = { system, ... }: {
  devShells.default = stc.devShells.${system}.ansible;
};
```

Available shells: `ansible`, `terraform`, `mdbook`, `mkdocs`, `zensical`, `vm`, `nixos`.

### Initialising a Template

```bash
mkdir my-playbooks && cd my-playbooks
nix flake init -t github:gfriloux/stc#ansible
```

Available templates: `ansible`, `terraform`, `mdbook`, `mkdocs`, `zensical`.

## What's Available

| Category | Reference |
|----------|-----------|
| NixOS modules (relics) | [Relics](/stc/en/relics/) |
| NixOS modules (profiles) | [Cogitator](/stc/en/cogitator/) |
| Home Manager modules | [Relics — Home Apps](/stc/en/relics/home-apps/), [Cogitator — Enginseer](/stc/en/cogitator/enginseer/) |
| Dev shells | [Forge — Shells](/stc/en/forge/shells/) |
| Flake templates | [Forge — Templates](/stc/en/forge/templates/) |
| Disk layouts | [Forge — Layouts](/stc/en/forge/layouts/) |
| Full examples | [Schematics](/stc/en/schematics/) |
