---
title: AWS
description: AWS EC2 configuration — Nitro/Xen drivers, NTP, serial console, EBS expansion, and ZFS pools.
---

**Module :** `stc.nixosModules.relics-aws`

Automatically configures NixOS to run on AWS EC2. Loads required drivers (NVMe, ENA), configures the serial console for AWS Systems Manager or EC2 Connect, synchronizes time via AWS internal NTP, and expands ZFS pools when the EBS volume is grown.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.aws.enable` | bool | `false` | Enable AWS EC2 configuration. |
| `stc.relics.aws.poolName` | string | — | Name of the ZFS pool to expand when EBS volume is resized. **Required.** |
| `stc.relics.aws.ebsDisk` | string | `"nvme0n1"` | EBS block device name (without `/dev/`). `nvme0n1` for Nitro instances, `xvda` for Xen. |
| `stc.relics.aws.ebsPartition` | int | `3` | Partition number holding the ZFS pool. Default: make-single-disk-zfs-image layout (bios_grub=1, ESP=2, ZFS=3). |

## What it does

- **Early boot drivers :** Loads `nvme`, `ena`, `xen_blkfront` (Nitro and Xen)
- **Blacklist xen_fbfront :** Prevents 30-second boot delay on Xen instances
- **Serial console :** Enables `ttyS0` for AWS Systems Manager or EC2 Connect (keyless SSH access)
- **NVMe timeouts :** Sets `nvme_core.io_timeout=4294967295` (Amazon EBS recommendation)
- **CPU RNG trust :** Sets `random.trust_cpu=on` to avoid first-boot entropy starvation on headless instances. Trade-off: it trusts the CPU vendor's RNG — reasonable when you already trust the hypervisor; remove it if your threat model differs.
- **AWS internal NTP :** Uses `169.254.169.123` — always available, no internet required
- **Disables udisks2 :** Removes unnecessary GTK dependencies from headless servers
- **Udev rules :** Installs `amazon-ec2-utils` for full compatibility
- **EBS expansion :** Boot-time oneshot (`stc-grow-pool`) that grows the partition and ZFS pool when the EBS volume is larger than the built image. Runs each boot (so it picks up a resized volume) but **not** on every `nixos-rebuild switch`, and surfaces real `growpart` failures instead of swallowing them

## Example usage

```nix
modules = [
  stc.nixosModules.relics-zfs
  stc.nixosModules.relics-aws
];

{
  stc.relics.zfs.enable = true;
  stc.relics.aws = {
    enable = true;
    poolName = "rpool";
    # ebsDisk = "nvme0n1";      # default: Nitro
    # ebsPartition = 3;         # default: partition 3
  };
}
```

For Xen (older instances) :

```nix
{
  stc.relics.aws = {
    enable = true;
    poolName = "rpool";
    ebsDisk = "xvda";
    ebsPartition = 3;
  };
}
```

## Combine with

- **[relics-zfs](/stc/en/relics/zfs)** (required) — ZFS pool for EBS expansion
- **[relics-impermanence](/stc/en/relics/impermanence)** — Recommended for ephemeral rootfs on EC2
- **schematic aws-ami** — Template to build NixOS AMIs
