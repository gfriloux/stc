---
title: Nix Housekeeping
description: A long-lived host bounds its Nix store and its journal on its own.
---

**Module:** `stc.nixosModules.relics-nix-housekeeping`

Stock NixOS lets the Nix store and the journal grow until the disk is full. On a
long-lived host nobody watches the disk, so the relic bounds both:

| Concern | Stock NixOS | What the relic does |
|---|---|---|
| Scheduled GC | Off | Weekly, deletes generations older than 30 days |
| Disk pressure during a build | Nothing until `No space left on device` | Below 5 GiB free, Nix collects garbage until 15 GiB are free |
| Store deduplication | Off | Weekly timer (`nix.optimise.automatic`) |
| Builds against served processes | Equal CPU, IO and OOM priority | Builds yield: CPU `batch`, IO `best-effort` 7, `OOMScoreAdjust=250` |
| Journal | 10% of the filesystem (up to 4G), no time limit | 500M, one month |

Enabled by default (`lib.mkDefault`) by
[docker-server](/stc/en/cogitator/docker-server/),
[dreadnought](/stc/en/cogitator/dreadnought/),
[sarcophagus-aws](/stc/en/cogitator/sarcophagus-aws/),
[sarcophagus-kvm](/stc/en/cogitator/sarcophagus-kvm/) and
[vm](/stc/en/cogitator/vm/), which keeps a 5-day GC window.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.nixHousekeeping.enable` | bool | `false` | Enable the relic |
| `stc.relics.nixHousekeeping.gc.enable` | bool | `true` | Scheduled GC (`nix.gc.automatic`) |
| `stc.relics.nixHousekeeping.gc.dates` | string | `"weekly"` | When the GC runs (systemd calendar expression) |
| `stc.relics.nixHousekeeping.gc.keepDays` | non-negative int | `30` | Delete generations and store paths older than this |
| `stc.relics.nixHousekeeping.minFreeGiB` | null or positive int | `5` | `nix.settings.min-free`; `null` turns off build-time collection |
| `stc.relics.nixHousekeeping.maxFreeGiB` | positive int | `15` | `nix.settings.max-free`; must be above `minFreeGiB` |
| `stc.relics.nixHousekeeping.optimise` | bool | `true` | Weekly store deduplication (skipped in a container) |
| `stc.relics.nixHousekeeping.deprioritiseBuilds` | bool | `true` | Builds and the GC yield to served processes |
| `stc.relics.nixHousekeeping.journal.systemMaxUse` | null or string | `"500M"` | journald `SystemMaxUse` |
| `stc.relics.nixHousekeeping.journal.maxRetentionSec` | null or string | `"1month"` | journald `MaxRetentionSec` |

Every setting the relic writes underneath is a `mkDefault`. If you write
`nix.gc.options` or a journald key yourself, your value wins without `mkForce`.

On a small disk (a default cloud root volume, a small qcow2), 5 and 15 GiB are
a large share of the disk, and nearly every build would collect garbage. Lower
both values there.

If you already clean the store with `nh clean` (`programs.nh.clean.enable`),
nixpkgs warns that it overlaps with `nix.gc.automatic`: set `gc.enable = false`.

## GC on a timer and GC under pressure are not the same thing

`nix.gc` is retention: once a week, old generations go. It does nothing for a
build that fills the disk on a Tuesday. `min-free` / `max-free` are the pressure
valve: when free space drops below `minFreeGiB` **during** a build, Nix collects
garbage until `maxFreeGiB` is free, and the build carries on. A remote
`nixos-rebuild switch` that runs out of space halfway is the failure this
prevents. You need both.

## Why a timer and not `auto-optimise-store`

`nix.settings.auto-optimise-store` deduplicates every path as it is built, so
every switch pays for it. The weekly timer gets the same deduplication, off the
critical path, and upstream already runs it at idle CPU and IO priority.

## How builds yield

With `deprioritiseBuilds`:

- The Nix daemon, and so every build, runs with CPU policy `batch` and IO class
  `best-effort` at its lowest priority (7).
- The daemon gets `OOMScoreAdjust=250`: under memory pressure, the kernel kills
  a build before a served process.
- The scheduled GC runs with CPU `batch` and IO `idle`.

The daemon's IO class is **not** `idle`, which is what srvos uses. Upstream's own
option description warns that `idle` can starve a configuration update on a
loaded machine, and on a server that update is the rebuild you need. A
dedicated build machine wants the opposite: set `deprioritiseBuilds = false`.

## Containers, and hosts without Nix

In a NixOS container the store belongs to the host, so its GC, deduplication
and disk pressure are the host's business. Under `boot.isContainer` the relic
skips the GC, `min-free` / `max-free` and the optimisation timer. nixpkgs turns
`nix.optimise.automatic` off there too, and the relic does not contradict it.

With `nix.enable = false` (an appliance image without Nix), the relic leaves
every Nix setting alone. Upstream would otherwise refuse `nix.gc.automatic`
without Nix.

The journal cap applies in both cases.

## Deliberately left out

`nix.gc.randomizedDelaySec` and a `--max-freed` GC mode were ruled out when the
relic was scoped. In this relic, `min-free` / `max-free` handle disk pressure.

## Proving

`provings/docker-server.nix` runs every check twice: on a node with the relic,
then on one with it off. It checks:

- `min-free` and `max-free` in `/etc/nix/nix.conf`;
- the `nix-gc` timer and its 30-day window;
- the scheduling and `OOMScoreAdjust` systemd actually applied to `nix-daemon`
  and `nix-gc`;
- the journald caps.

Each check must pass on the first node and fail on the second.
`provings/vm.nix` is unchanged and still checks vm's 5-day window, which proves
the options kept their behaviour when they moved.

## See Also

- [VM profile](/stc/en/cogitator/vm/): the renamed `stc.cogitator.vm.nix.gc.*` options
- [Server Survivability](/stc/en/relics/server-survivability/)
