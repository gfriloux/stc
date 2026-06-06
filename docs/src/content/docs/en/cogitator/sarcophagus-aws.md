---
title: Sarcophagus AWS Profile
description: cogitator-sarcophagus-aws — NixOS AMI disk image with ZFS, impermanence, and hardening.
---

**Module:** `stc.nixosModules.cogitator-sarcophagus-aws`

The Sarcophagus is the hermetically sealed pod that preserves the remains of a mortally wounded Space Marine. This cogitator seals your system into a raw disk image inscribed with ZFS, impermanence, and hardening: the inert sarcophagus, preserving your configuration's essence while awaiting deployment on the AWS battlefields. Once imported as an AMI and awakened in an EC2 instance, this sarcophagus becomes the living core of the complete Dreadnought.

Builds a raw NixOS disk image suitable for import as an AWS AMI, with ZFS,
impermanence, and full hardening. Includes the AWS platform relic (NVMe/ENA
drivers, NTP, serial console, EBS pool expansion) and embeds the disk layout
and image builder — no external `disko` import required.

Instances deployed from this AMI are intended to be managed with
[cogitator-dreadnought](/stc/en/cogitator/dreadnought/).

## What It Composes

| Component | What it does |
|-----------|-------------|
| `relics-zfs` | ZFS-compatible kernel, auto-scrub, TRIM, ZED |
| `relics-networking` | DHCP, Quad9 DNS |
| `relics-impermanence` | Root rollback to `@blank` on every boot |
| `relics-aws` | NVMe/ENA drivers, NTP, serial console, EBS pool expansion |
| `cogitator-hardening` | Kernel + network + filesystem + SSH hardening |
| Disko layout | GPT on `/dev/vda` — 1 GiB FAT32 `/boot` + ZFS pool |
| GRUB override | BIOS/GRUB required by `make-single-disk-zfs-image.nix` |
| `system.build.awsImage` | Raw image builder |

`disko.nixosModules.disko` and `impermanence.nixosModules.impermanence` are
injected automatically — the consumer does not need to import them.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.sarcophagus-aws.enable` | bool | `false` | Enable this cogitator |
| `stc.cogitator.sarcophagus-aws.poolName` | str | `"vmpool"` | ZFS pool name |
| `stc.cogitator.sarcophagus-aws.rootSize` | int | `4096` | Disk image size in MiB |
| `stc.cogitator.sarcophagus-aws.memSize` | int | `4096` | Build VM memory in MiB |
| `stc.cogitator.sarcophagus-aws.ebsDisk` | str | `"nvme0n1"` | EBS device name (without `/dev/`). Use `xvda` for Xen instances. |
| `stc.cogitator.sarcophagus-aws.ebsPartition` | int | `3` | ZFS pool partition number on the EBS disk |
| `stc.cogitator.sarcophagus-aws.impermanence.extraDirectories` | list of str | `[]` | Additional directories to persist |
| `stc.cogitator.sarcophagus-aws.impermanence.extraFiles` | list of str | `[]` | Additional files to persist |

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
    nixosConfigurations.my-ami = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-sarcophagus-aws
        ({ ... }: {
          stc.cogitator.sarcophagus-aws = {
            enable = true;
            impermanence.extraDirectories = [ "/var/db/sudo/lectured" ];
          };
          networking.hostName = "my-ami";
          networking.hostId = "cafebabe"; # replace — must be unique
          users = {
            mutableUsers = false;
            users.admin = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... you@host" ];
            };
          };
          security.sudo.wheelNeedsPassword = false;
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

Build and publish:

```bash
nix build .#nixosConfigurations.my-ami.config.system.build.awsImage
# result/nixos.root.img is the raw disk image to import as a snapshot
```

:::caution[SSH key required]
`cogitator-hardening` disables SSH password authentication. Add your public key
to `openssh.authorizedKeys.keys` before building — you will not be able to log
in otherwise.
:::

:::caution[Change the hostId]
`networking.hostId = "cafebabe"` is a placeholder. Every ZFS host must have a
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

At runtime on EC2, `relics-aws` runs `growpart` + `zpool online -e` to expand
the ZFS pool to the full EBS volume size.

## See Also

- [aws-ami schematic](/stc/en/schematics/aws-ami/) — ready-to-use example built on this cogitator
- [cogitator-dreadnought](/stc/en/cogitator/dreadnought/) — profile for instances deployed from this AMI
- [relics-aws](/stc/en/relics/aws/) — the AWS platform relic
- [relics-impermanence](/stc/en/relics/impermanence/) — how the root rollback works
- [cogitator-sarcophagus-kvm](/stc/en/cogitator/sarcophagus-kvm/) — the KVM variant
