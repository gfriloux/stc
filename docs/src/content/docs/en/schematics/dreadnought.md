---
title: dreadnought
description: A NixOS EC2 instance deployed from a sarcophagus-aws AMI, managed via deploy-rs.
---

**Source:** `schematics/dreadnought/`

A NixOS system configuration for an EC2 instance launched from a
[sarcophagus-aws](/stc/en/schematics/aws-ami/) AMI, deployed and managed via
[deploy-rs](https://github.com/serokell/deploy-rs).

This schematic does not build a disk image — it builds a NixOS system closure
and deploys it onto a running instance. The disk was already partitioned by the
sarcophagus-aws AMI.

## Prerequisites

- An EC2 instance running a NixOS AMI built with `cogitator-sarcophagus-aws`
- Nix with flakes enabled on the build machine
- `deploy-rs` available (provided by the schematic's devShell)
- SSH access from your build machine to the EC2 instance (port 22, as user `admin`)

## Setup

### 1. Fetch the kernel modules

SSH into the running EC2 instance and run:

```bash
nixos-generate-config --show-hardware-config
```

Copy only the `boot.initrd.availableKernelModules` and `boot.kernelModules`
lines into `hardware-configuration.nix`. The ZFS filesystem layout and GRUB
boot loader are already handled by `cogitator-dreadnought` and must not be
duplicated.

### 2. Set the hostname

In `flake.nix`, update `deploy.nodes.dreadnought.hostname` and the Justfile
`HOST` variable to your instance's public IP or DNS name.

### 3. Match the AMI values

The following must match the values used when building the sarcophagus-aws AMI:

- `networking.hostId` — copy from the AMI's `flake.nix`
- `stc.cogitator.dreadnought.poolName` — default `"vmpool"` unless overridden

### 4. Add your SSH key

Add your public key to `users.users.admin.openssh.authorizedKeys.keys`.

:::danger[Do not deploy as-is]
This schematic ships `users.allowNoPasswordLogin = true` (only so it evaluates
before you add a key), `security.sudo.wheelNeedsPassword = false` (passwordless
sudo for wheel), and a placeholder `networking.hostId = "cafebabe"`. After adding
your SSH key, set `allowNoPasswordLogin = false` and replace the hostId. With
key-only SSH and passwordless sudo, anyone holding `admin`'s key has a direct
root path — make that an intentional choice.
:::

## Modules Used

| Module | Purpose |
|--------|---------|
| `stc.nixosModules.cogitator-dreadnought` | ZFS + impermanence + hardening + AWS platform + ZFS layout + GRUB |
| `./hardware-configuration.nix` | EC2-instance-specific kernel modules |

## Justfile Recipes

```bash
just build    # build the system closure (does not deploy)
just deploy   # deploy to the EC2 instance via deploy-rs
just ssh      # SSH into the instance
just check    # nix flake check (includes deploy-rs schema checks)

just fmt      # alejandra format
just ci       # fmt-check + lint
just update   # update flake inputs
```

## Adding Service Profiles

Uncomment and configure additional cogitators in `flake.nix`:

```nix
modules = [
  stc.nixosModules.cogitator-dreadnought
  stc.nixosModules.cogitator-docker-server  # Traefik + CrowdSec + ntfy
  stc.nixosModules.cogitator-vm             # fish, SSH, admin user
  ./hardware-configuration.nix
  ({ ... }: {
    stc.cogitator.dreadnought.enable = true;
    stc.cogitator.docker-server.enable = true;
    stc.cogitator.vm = { enable = true; username = "admin"; authorizedKeys = [ ... ]; };
    # ...
  })
];
```

## deploy-rs Configuration

The schematic wires deploy-rs with `sshUser = "admin"` and `user = "root"`.
deploy-rs will SSH as `admin` and use `sudo` to switch the system profile as root.

The `checks` output integrates deploy-rs schema validation into `nix flake check`,
catching configuration errors before deployment.

## See Also

- [cogitator-dreadnought](/stc/en/cogitator/dreadnought/) — full options reference
- [aws-ami schematic](/stc/en/schematics/aws-ami/) — builds the AMI this runs on
- [cogitator-sarcophagus-aws](/stc/en/cogitator/sarcophagus-aws/) — the AMI builder cogitator
