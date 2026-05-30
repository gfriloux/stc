---
title: Layouts
description: Disko disk partition layouts for STC-managed machines.
---

Forge layouts are [Disko](https://github.com/nix-community/disko) partition
definitions. They are pure Nix functions — call them with your parameters and
include the result in your `nixosSystem` modules list.

## zfs-local-vm

**Function:** `stc.lib.layouts.zfs-local-vm`

**Signature:** `{ poolName ? "vmpool" }`

Disk layout for a QEMU/KVM local virtual machine. Targets `/dev/vda`
(virtio-blk device). Pair with `relics-boot` and `relics-impermanence`.

### Partition Table

| Partition | Size | Type | Mount |
|-----------|------|------|-------|
| ESP | 1 GiB | vfat | `/boot` |
| ZFS | Remainder | ZFS | — |

### ZFS Pool

| Dataset | Mount | Purpose |
|---------|-------|---------|
| `poolName/root` | `/` | Ephemeral root — rolled back to `@blank` at every boot |
| `poolName/nix` | `/nix` | Persistent Nix store |
| `poolName/persist` | `/persist` | Explicit persistent state |

Pool options: `ashift=12` (4K sector alignment), `compression=lz4`, `atime=off`,
`xattr=sa`, `acltype=posixacl`, all datasets use legacy mountpoints.

A `@blank` snapshot is created on `poolName/root` immediately after the pool is
created (`postCreateHook`). This is the snapshot that `relics-impermanence` rolls
back to on every boot.

### Usage in nixosSystem

```nix
# flake.nix
{ nixpkgs, stc, ... }:
{
  nixosConfigurations.my-vm = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      stc.inputs.disko.nixosModules.disko
      stc.inputs.impermanence.nixosModules.impermanence

      stc.nixosModules.relics-boot
      stc.nixosModules.relics-zfs
      stc.nixosModules.relics-impermanence

      # Disk layout — call with your pool name
      (stc.lib.layouts.zfs-local-vm { poolName = "vmpool"; })

      ./configuration.nix
    ];
  };
}
```

```nix
# configuration.nix
{
  stc.boot.enable = true;
  stc.zfs.enable = true;
  stc.impermanence = {
    enable = true;
    poolName = "vmpool";   # must match the layout argument
  };

  # virtio drivers — required for /dev/vda to exist in the initrd
  boot.initrd.kernelModules = [ "virtio_pci" "virtio_blk" ];

  # virtio disks have no by-id entries in QEMU
  boot.zfs.devNodes = "/dev";

  networking.hostName = "my-vm";
  networking.hostId = "a1b2c3d4";  # unique per machine
}
```

:::caution[Disko input]
The layout uses Disko declarations. You must include `stc.inputs.disko.nixosModules.disko`
in your modules list, or provide disko from your own inputs. Without the disko module,
the `disko.devices` option does not exist and evaluation will fail.
:::

:::tip[virtio and devNodes]
QEMU virtio disks do not create entries under `/dev/disk/by-id/`. ZFS defaults to
searching there. Set `boot.zfs.devNodes = "/dev"` to use the raw device path instead.
Also add `virtio_pci` and `virtio_blk` to `boot.initrd.kernelModules` so the disk is
visible in the initrd before ZFS tries to import the pool.
:::

## See Also

- [Schematic: local-vm](/en/schematics/local-vm/) — complete example using this layout
- [relics-boot](/en/relics/boot/) — provides the ZFS kernel
- [relics-impermanence](/en/relics/impermanence/) — uses the `@blank` snapshot created here
