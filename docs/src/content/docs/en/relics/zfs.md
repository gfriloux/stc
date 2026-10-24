---
title: ZFS
description: ZFS kernel, boot support, and pool maintenance — scrub, TRIM, ZED.
---

**Module:** `stc.nixosModules.relics-zfs`

Everything NixOS needs to run ZFS: the right kernel, filesystem support in the
initrd, pool import settings, and ongoing maintenance (scrub, TRIM, ZED).

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.zfs.enable` | bool | `false` | Enable ZFS kernel, boot support, and pool maintenance |
| `stc.relics.zfs.kernel` | enum `"lts"` \| `"latest"` | `"lts"` | Which ZFS-compatible kernel to track. `"lts"` = newest LTS (stable, minimal churn); `"latest"` = newest compatible (follows nixpkgs closely). |
| `stc.relics.zfs.scrubInterval` | string | `"monthly"` | systemd calendar expression for auto-scrub |
| `stc.relics.zfs.autoSnapshot.enable` | bool | `false` | Enable periodic ZFS snapshots on the persist dataset |
| `stc.relics.zfs.autoSnapshot.daily` | int | `7` | Number of daily snapshots to keep |
| `stc.relics.zfs.autoSnapshot.poolName` | string | — | ZFS pool name (required if autoSnapshot.enable = true) |

## What It Does

**Kernel** — selects a kernel compatible with the out-of-tree ZFS module (ZFS
occasionally lags behind the kernel; a mismatched pair fails to build). With
`kernel = "lts"` (default) it takes nixpkgs' default kernel (`pkgs.linuxPackages`,
the newest LTS series) — the same kernel a machine without ZFS gets — and only
falls back to an older ZFS-compatible LTS series if ZFS does not support that
one yet. Stable and low-churn, the right choice for production. With
`kernel = "latest"` it picks the newest compatible kernel, tracking nixpkgs
closely. LTS releases stay ZFS-compatible longest; non-LTS kernels often reach
EOL before ZFS supports the next one.

A machine **without** this relic is not restricted at all: STC leaves
`boot.kernelPackages` to nixpkgs.

**Filesystem support** — adds `"zfs"` to `boot.supportedFilesystems` and
`boot.initrd.supportedFilesystems` so the initrd can import pools at boot.

**Pool import** — sets `boot.zfs.forceImportRoot = lib.mkDefault false`: the
root pool is imported **without** `-f`, so ZFS keeps the check that refuses a
pool whose hostId belongs to another system. `forceImportAll` stays `false`
too, for non-root pools.

**Auto-scrub** — runs `zpool scrub` on all pools at `scrubInterval`. Monthly is
sufficient for most workloads; use `"weekly"` on write-heavy systems or large
pools.

**TRIM** — sends discard commands to SSDs and thin-provisioned virtual disks,
recovering space and maintaining write performance.

**ZED (ZFS Event Daemon)** — monitors pool health and logs errors.

## Usage Example

```nix
modules = [
  stc.nixosModules.relics-boot
  stc.nixosModules.relics-zfs
  ./configuration.nix
];

# configuration.nix
{
  stc.relics.boot.enable = true;
  stc.relics.zfs = {
    enable = true;

    # Optional: periodic snapshots
    autoSnapshot = {
      enable = true;
      poolName = "vmpool";   # snapshots enabled on vmpool/persist only
      daily = 14;            # optional: keep 14 days instead of 7
    };

    # Optional: scrub weekly on write-heavy pools
    scrubInterval = "weekly";
  };

  # ZFS requires a unique hostId per machine.
  # Generate: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
  networking.hostId = "a1b2c3d4";
}
```

:::tip[scrubInterval format]
The value is a systemd calendar expression. Valid values include `"daily"`,
`"weekly"`, `"monthly"`, or a full expression like `"Sun *-*-* 02:00:00"`.
:::

:::note[ZFS hostId]
ZFS uses `networking.hostId` to identify the importing host. This prevents a pool
that was last used on machine A from being silently imported on machine B. Generate a
unique 8-character hex string for every machine.

STC does **not** pin a default hostId. [srvos](https://github.com/nix-community/srvos)
defaults it to the install ISO's `8425e349` so that imports always match; that
removes the one-time mismatch at the price of making every host claim the same
identity — two of them would import the same pool without ZFS objecting. A
unique hostId per machine is the stricter half of what makes the unforced import
worth anything.
:::

:::caution[If your root pool carries a foreign hostId]
A pool that was last imported by another system — a disk moved between machines,
a pool created by an installer that was never exported — will now refuse to
import, and the host stops at the initrd instead of booting. Two ways out:

- **One-off, at the bootloader:** add `zfs_force=1` to the kernel command line
  for a single boot, then `zpool export <pool>` and let the next boot import it
  cleanly. Both stage-1 implementations (scripted and systemd) honour the
  parameter.
- **Permanently, if your setup genuinely needs it:** put
  `boot.zfs.forceImportRoot = true;` in your configuration. The relic's value is
  a `mkDefault`, so a plain definition wins — no `lib.mkForce` needed. Writing
  `lib.mkDefault true` instead collides with the relic's own `mkDefault` and
  fails evaluation.

Installing with `nixos-anywhere` (no STC schematic does — all three build an
image) leaves the pool imported with the installer's hostId. Run
`zpool export <pool>` before the first reboot and the import needs no force.
Upstream makes `false` the default from `stateVersion` 26.11 on, so this is
where NixOS is heading regardless.
:::

## Pair With

- [`relics-boot`](/stc/en/relics/boot/) — systemd-boot + EFI bootloader
- [`relics-impermanence`](/stc/en/relics/impermanence/) — root rollback at each boot
- [`forge/layouts/zfs-local-vm`](/stc/en/forge/layouts/) — disko disk layout
