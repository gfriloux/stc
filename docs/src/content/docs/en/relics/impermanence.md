---
title: Impermanence
description: ZFS-based impermanence — root dataset rolled back to @blank at every boot.
---

**Module:** `stc.nixosModules.relics-impermanence`

Every boot is a fresh start. The machine forgets. Only `/persist` remembers.

On first boot, a `@blank` snapshot is taken of the root dataset automatically.
On every subsequent boot, the root dataset is rolled back to that snapshot in the
initrd — before systemd starts — so the system always comes up clean.

Anything that should survive reboots must be explicitly declared in
`extraDirectories` or `extraFiles`. If it is not listed, it is gone after reboot.
This is a feature, not a bug.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.impermanence.enable` | bool | `false` | Enable ZFS-based impermanence |
| `stc.impermanence.poolName` | string | `"rpool"` | ZFS pool containing the root dataset |
| `stc.impermanence.datasetName` | string | `"root"` | Dataset to roll back at each boot |
| `stc.impermanence.persistPath` | string | `"/persist"` | Mount point of the persistent ZFS dataset |
| `stc.impermanence.extraDirectories` | list of strings | `[]` | Additional directories to bind-mount from `persistPath` into `/` |
| `stc.impermanence.extraFiles` | list of strings | `[]` | Additional files to bind-mount from `persistPath` into `/` |

## What It Does

**Rollback service** — a systemd stage-1 initrd service (`zfs-rollback`) that runs
after the ZFS pool is imported but before the root filesystem is mounted. On first
run it creates `poolName/datasetName@blank`. On every subsequent run it rolls back
to that snapshot.

**Persistent mount** — mounts `poolName/persist` at `persistPath` with
`neededForBoot = true`, so SSH host keys and secrets are available early.

**Always-persistent paths** — the following paths are always persisted, regardless
of `extraDirectories` / `extraFiles`:

| Path | Why |
|------|-----|
| `/var/lib/nixos` | NixOS UID/GID tracking across activations |
| `/var/log` | Logs for audit and debugging |
| `/etc/machine-id` | Stable systemd identity (journald breaks if this changes) |
| `/etc/ssh/ssh_host_rsa_key` (and `.pub`) | SSH host keys |
| `/etc/ssh/ssh_host_ed25519_key` (and `.pub`) | SSH host keys |

## Usage Example

```nix
# flake.nix
modules = [
  stc.inputs.impermanence.nixosModules.impermanence  # upstream impermanence module
  stc.nixosModules.relics-impermanence
  ./configuration.nix
];

# configuration.nix
{
  stc.impermanence = {
    enable = true;
    poolName = "vmpool";      # must match your disko layout
    # datasetName = "root";   # default is fine if your dataset is poolName/root
    # persistPath = "/persist"; # default is fine

    extraDirectories = [
      "/var/db/sudo/lectured"   # sudo lecture state
      "/var/lib/docker"         # Docker data (if using Docker)
    ];

    extraFiles = [
      "/etc/nix/id_rsa"         # example: a deploy key
    ];
  };
}
```

:::caution[Import the upstream module]
`relics-impermanence` requires the upstream `impermanence` NixOS module.
Import it via `stc.inputs.impermanence.nixosModules.impermanence` or from
your own `impermanence` flake input.
:::

:::tip[initrd systemd]
The rollback runs in the systemd stage-1 initrd. This means
`boot.initrd.systemd.enable` is set to `true` by this relic. The older
`postDeviceCommands` hook is not used.
:::

## Pair With

- [`relics-boot`](/stc/en/relics/boot/) — required for ZFS initrd support
- [`forge/layouts/zfs-local-vm`](/stc/en/forge/layouts/) — creates the ZFS pool and datasets
