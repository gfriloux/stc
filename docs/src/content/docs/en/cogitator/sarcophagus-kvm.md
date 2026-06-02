---
title: Sarcophagus KVM Profile
description: cogitator-sarcophagus-kvm — QEMU/KVM NixOS disk image with ZFS, impermanence, and hardening.
---

**Module:** `stc.nixosModules.cogitator-sarcophagus-kvm`

The Sarcophagus is the artificial life-support pod integrated into a Dreadnought's chassis, preserving the mortally wounded Space Marine in stasis between battles. This NixOS cogitator encases your configuration in a sealed, immutable qcow2 image—a hermetically preserved chamber awaiting deployment to any KVM hypervisor. The image is the Sarcophagus: the sealed vessel of your system's essence before it awakens on the battlefield.

Builds a QEMU/KVM NixOS disk image (qcow2) ready to boot on any KVM hypervisor.
Composes ZFS, networking, impermanence, and the full hardening suite, and embeds
the disk layout and image builder — no external `disko` import required.

## What It Composes

| Component | What it does |
|-----------|-------------|
| `relics-zfs` | ZFS-compatible kernel, auto-scrub, TRIM, ZED |
| `relics-networking` | DHCP, Quad9 DNS |
| `relics-impermanence` | Root rollback to `@blank` on every boot |
| `cogitator-hardening` | Kernel + network + filesystem + SSH hardening |
| Disko layout | GPT on `/dev/vda` — 1 GiB FAT32 `/boot` + ZFS pool |
| GRUB override | BIOS/GRUB required by `make-single-disk-zfs-image.nix` |
| `system.build.qcow2` | qcow2 image builder |

`disko.nixosModules.disko` and `impermanence.nixosModules.impermanence` are
injected automatically — the consumer does not need to import them.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.sarcophagus-kvm.enable` | bool | `false` | Enable this cogitator |
| `stc.cogitator.sarcophagus-kvm.poolName` | str | `"vmpool"` | ZFS pool name |
| `stc.cogitator.sarcophagus-kvm.rootSize` | int | `20480` | Disk image size in MiB |
| `stc.cogitator.sarcophagus-kvm.memSize` | int | `4096` | Build VM memory in MiB |
| `stc.cogitator.sarcophagus-kvm.impermanence.extraDirectories` | list of str | `[]` | Additional directories to persist under `/persist` |
| `stc.cogitator.sarcophagus-kvm.impermanence.extraFiles` | list of str | `[]` | Additional files to persist under `/persist` |

## Usage Example

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
    nixosConfigurations.my-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-sarcophagus-kvm
        stc.nixosModules.cogitator-vm   # optional: fish, SSH, admin user
        ({ ... }: {
          stc.cogitator.sarcophagus-kvm = {
            enable = true;
            impermanence.extraDirectories = [ "/var/db/sudo/lectured" ];
          };
          stc.cogitator.vm = {
            enable = true;
            username = "admin";
            authorizedKeys = [ "ssh-ed25519 AAAA... you@host" ];
          };
          networking.hostName = "my-vm";
          networking.hostId = "deadc0de"; # replace — must be unique
          users.mutableUsers = false;
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

Build the image:

```bash
nix build .#nixosConfigurations.my-vm.config.system.build.qcow2
qemu-system-x86_64 -enable-kvm -m 4096 -drive file=result,format=qcow2
```

:::caution[Change the hostId]
`networking.hostId = "deadc0de"` is a placeholder. Every ZFS host must have a
unique hostId. Generate one: `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
:::

## Disk Layout

```
/dev/vda (GPT)
├── partition 1 — 1 GiB  FAT32  /boot   (label: ESP)
└── partition 2 — 100%   ZFS pool (vmpool by default)
    ├── vmpool/root    →  /        ephemeral — rolled back to @blank each boot
    ├── vmpool/nix     →  /nix     persistent — the Nix store
    └── vmpool/persist →  /persist persistent — explicit state only
```

## See Also

- [local-vm schematic](/stc/en/schematics/local-vm/) — ready-to-use example built on this cogitator
- [relics-impermanence](/stc/en/relics/impermanence/) — how the root rollback works
- [cogitator-hardening](/stc/en/cogitator/hardening/) — the hardening suite this composes
- [cogitator-sarcophagus-aws](/stc/en/cogitator/sarcophagus-aws/) — the AWS variant
