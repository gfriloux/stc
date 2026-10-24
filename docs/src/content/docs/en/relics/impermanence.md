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
| `stc.relics.impermanence.enable` | bool | `false` | Enable ZFS-based impermanence |
| `stc.relics.impermanence.poolName` | string | `"rpool"` | ZFS pool containing the root dataset |
| `stc.relics.impermanence.datasetName` | string | `"root"` | Dataset to roll back at each boot |
| `stc.relics.impermanence.persistPath` | string | `"/persist"` | Mount point of the persistent ZFS dataset |
| `stc.relics.impermanence.persistDataset` | string | `"persist"` | Name of the persistent ZFS dataset under `poolName`, mounted at `persistPath` |
| `stc.relics.impermanence.extraDirectories` | list of strings | `[]` | Additional directories to bind-mount from `persistPath` into `/` |
| `stc.relics.impermanence.extraFiles` | list of strings | `[]` | Additional files to bind-mount from `persistPath` into `/` |
| `stc.relics.impermanence.onRollbackFailure` | `"continue"` \| `"emergency"` | `"continue"` | What a failed rollback does to the boot — see [When the rollback fails](#when-the-rollback-fails) |

## What It Does

**Rollback service** — a systemd stage-1 initrd service (`zfs-rollback`) that runs
after the ZFS pool is imported but before the root filesystem is mounted. On first
run it creates `poolName/datasetName@blank`. On every subsequent run it rolls back
to that snapshot.

**Outcome reporting** — `stc-impermanence-state.service` in the booted system,
which reads what the initrd left in `/run` and fails if the rollback did.

**Persistent mount** — mounts `poolName/persistDataset` (default `poolName/persist`)
at `persistPath` with `neededForBoot = true`, so SSH host keys and secrets are
available early.

**Always-persistent paths** — the following paths are always persisted, regardless
of `extraDirectories` / `extraFiles`:

| Path | Why |
|------|-----|
| `/var/lib/nixos` | NixOS UID/GID tracking across activations |
| `/var/log` | Logs for audit and debugging |
| `/etc/machine-id` | Stable systemd identity (journald breaks if this changes) |
| `/etc/ssh/ssh_host_rsa_key` (and `.pub`) | SSH host keys |
| `/etc/ssh/ssh_host_ed25519_key` (and `.pub`) | SSH host keys |

## When the rollback fails

The promise at the top of this page is an integrity promise: a machine that
starts clean is a machine an attacker cannot persist on by writing to the root.
A rollback that fails breaks that promise — the host comes up carrying whatever
the previous boot left behind.

**By default the boot continues.** `onRollbackFailure = "continue"` keeps the
host reachable, which is almost always what you want on a server you cannot walk
up to. What changed is that the failure is no longer silent:

- the initrd script leaves a marker in `/run`, which survives `switch-root`;
- `stc-impermanence-state.service` reads it and **fails**, so the unit shows up
  in `systemctl --failed` and `systemctl is-system-running` reports `degraded`.

That matters because the `zfs-rollback` unit itself has no fragment in the booted
system — before this, a failed rollback left nothing but a line in an initrd
journal nobody reads.

**If you would rather not boot at all**, set:

```nix
stc.relics.impermanence.onRollbackFailure = "emergency";
```

The rollback service then pulls in `emergency.target` from the initrd and the
boot stops. Know the price first: `boot.initrd.systemd.emergencyAccess` defaults
to `false`, which locks the root account in the initrd, so there is **no shell**
at the emergency prompt. A headless host that lands there has to be rescued out
of band. Set `emergencyAccess` alongside it if you want to be able to take over.

One nuance, because "the boot stops" is not quite a hard stop: `OnFailure`
*starts* `emergency.target`, it does not cancel the boot. With the root account
locked, `sulogin` prints that it cannot open the console and waits indefinitely,
so a headless host does hang — which is the intended outcome. But anyone at a
console who presses Enter resumes the boot, with the dirty root. Treat
`emergency` as "a human must decide", not as "this host cannot come up".

On the four server profiles,
[Server Survivability](/stc/en/relics/server-survivability/) puts
`boot.panic_on_fail` on the command line, which turns that stop into a reboot
loop. The combination is refused at build time. Set
`stc.relics.serverSurvivability.panicReboot = false;` alongside `emergency`.

## If `@blank` goes missing

The snapshot is created automatically when it is absent, because nothing else
creates it — the image builders ship no snapshot, so without this a fresh disk
would never boot.

The consequence is worth stating plainly, because it is the one way this relic
can break its promise while reporting success. If `@blank` is destroyed — by
hand, or by restoring a pool from a `zfs send` that did not include it — the next
boot takes a **new** snapshot of the root dataset *as it is at that moment*, and
that becomes the permanent definition of "clean" for every boot after it. If the
root was dirty, it stays dirty, forever, and the rollback keeps succeeding.

The relic cannot tell a genuine first boot from a lost reference, so it does not
guess. It says so instead, twice: a warning in the initrd journal naming the
dataset, and a second marker that makes `stc-impermanence-state.service` log the
same thing in the booted system. Seeing that message on a host that is not being
installed means the clean reference is gone and should be re-established
deliberately.

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
  stc.relics.impermanence = {
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
