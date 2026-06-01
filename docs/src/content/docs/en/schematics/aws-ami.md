---
title: aws-ami
description: A NixOS AMI for AWS EC2 with ZFS, impermanence, and hardening.
---

**Source:** `schematics/aws-ami/`

A NixOS AMI image for AWS EC2, with ZFS storage, impermanence, and full hardening.
The AMI uses the same `zfs-local-vm` disk layout as the local-vm schematic — the
ZFS pool structure is identical.

## Prerequisites

### Local setup

- Nix with flakes enabled
- AWS CLI configured (`aws configure`)

### AWS one-time setup

1. Create an S3 bucket for image uploads
2. Create the `vmimport` IAM role with the permissions from the [AWS VM Import documentation](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html)

### Before building

In `flake.nix`, edit at minimum:

- `networking.hostId` — generate a unique value: `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
- `openssh.authorizedKeys.keys` — add your SSH public key

SSH password authentication is disabled by `cogitator-hardening`. Without an SSH
key, you will not be able to connect to the instance.

## Modules Used

| Module | Purpose |
|--------|---------|
| `disko.nixosModules.disko` | Declarative disk partitioning |
| `stc.nixosModules.relics-boot` | systemd-boot + ZFS-compatible kernel |
| `stc.nixosModules.relics-zfs` | Auto-scrub, TRIM, ZED |
| `stc.nixosModules.relics-networking` | DHCP, Quad9 DNS |
| `stc.nixosModules.relics-impermanence` | Root rollback on each boot |
| `stc.nixosModules.cogitator-hardening` | Full hardening suite |
| `stc.lib.layouts.zfs-local-vm` | EFI + ZFS disk layout |
| `./image.nix` | Raw image builder (GRUB override for build) |

## AWS-Specific Kernel Modules

AWS instances require drivers for Nitro (modern) and Xen (legacy) hardware:

```nix
# Nitro instances: NVMe storage + ENA networking
# Xen instances: block device + network frontend
boot.initrd.availableKernelModules = [ "nvme" "xen_blkfront" ];
boot.kernelModules = [ "ena" "xen_netfront" ];
```

## Justfile Recipes

```bash
just update    # update flake inputs

just build     # builds result/nixos.root.img (raw format, ~5-10 minutes)
just run       # boot the image in QEMU/KVM for local testing
just ssh       # SSH into the local VM (port 2222)

just publish   # uploads to S3, imports snapshot, registers AMI
```

`publish` requires: `just build` completed, `AMI_BUCKET` set in the Justfile,
and AWS CLI configured.

The full publish flow:
1. Upload raw image to `s3://AMI_BUCKET/AMI_NAME.img`
2. Import as EC2 snapshot (`aws ec2 import-snapshot`)
3. Poll until the import completes
4. Register the snapshot as an AMI (`aws ec2 register-image`)

## image.nix

Same GRUB/BIOS override as `local-vm/qcow2.nix`. The `make-single-disk-zfs-image.nix`
builder creates a BIOS partition layout; GRUB is forced for the build. The registered
AMI boots correctly because GRUB uses partition UUIDs, not device names.

The image is built in `raw` format (not qcow2) — AWS `import-snapshot` requires
a raw disk image.

## See Also

- [Forge — Layouts](/stc/en/forge/layouts/) — the `zfs-local-vm` disk layout
- [cogitator-hardening](/stc/en/cogitator/hardening/) — the hardening profile used here
- [relics-impermanence](/stc/en/relics/impermanence/) — how the rollback works
