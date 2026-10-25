---
title: polkit unit delegation
description: Let a group start, stop or restart named systemd units without sudo.
---

**Module:** `stc.nixosModules.relics-polkit-units`

`sudo systemctl restart docker-immich-server` works, but `sudo systemctl`
grants control of **every** unit on the host. Usually the need is narrower:
restart one container, or start an on-demand service declared with
`wantedBy = lib.mkForce []`. The relic generates the polkit rule that grants
exactly that:

```nix
stc.relics.polkitUnits = {
  enable = true;
  delegations = [
    {
      group = "ops";
      units = ["docker-immich-server" "docker-immich-redis"];
    }
  ];
};
```

A member of `ops` then runs `systemctl restart docker-immich-server`, without
sudo and without a password.

No cogitator enables it.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.polkitUnits.enable` | bool | `false` | Enable the relic (also enables polkit) |
| `stc.relics.polkitUnits.delegations` | list | `[]` | Who may do what to which units. Empty grants nothing |
| `delegations.*.group` | string | — | Group whose members receive the delegation. Must exist in `users.groups` |
| `delegations.*.units` | list of strings | `[]` | Exact unit names, as systemd ids. `.service` is added to a name with no type suffix. Each must be installed by this configuration |
| `delegations.*.unitPrefixes` | list of non-empty strings | `[]` | Prefixes, expanded at build time to the installed units they match |
| `delegations.*.actions` | list of verbs | `["start" "stop" "restart"]` | Granted verbs: `start`, `stop`, `restart`, `try-restart`, `reload`, `reload-or-restart`, `reload-or-try-restart` |

The build fails when a delegation:

- names no unit and no prefix;
- names a unit this configuration does not install;
- has a prefix that matches no installed unit.

## Every granted name must exist

`systemd-run` asks polkit for the same permission as `systemctl start`, with
the unit name **the caller chooses**. systemd refuses to create a transient
unit under a name that already has a unit file, and accepts any other name.
So a rule that matched a name with no unit file would let a member run
`systemd-run --unit=<that name> <any command>` **as root**. Such a name can be:

- a unit added later under a prefix;
- a typo;
- a unit you disabled.

That is why the relic resolves every name at build time:

- an exact name must be a unit this configuration installs (`systemd.services`,
  a container's unit, …), or an instance of an installed template
  (`foo@bar` when `foo@` is declared);
- a prefix becomes the list of installed units it matches;
- the rule compares against that closed list and matches no pattern at runtime.

A unit shipped only by a package (`systemd.packages`) is not in that list.
Declare it with an empty `systemd.services.<name> = {};` to delegate it.

## What group membership now means

:::caution[This widens privileges]
A member of a delegated group can stop the listed units, and so stop whatever
they serve. Restarting a unit also runs its `ExecStartPre`/`ExecStart` again as
the unit's user, which is often root. They cannot change what a listed unit
runs: its unit file is in the Nix store. Add people to that group the way you
would add them to `wheel` for those units.
:::

Two effects come with any start or stop, and polkit cannot restrict either:

- **Dependencies follow.** Stopping a unit also stops what `Requires=` or
  `BindsTo=` it. Starting one also starts what it `Requires=` or `Wants=`.
- **The caller picks the job mode.** `systemctl start --job-mode=flush` cancels
  every queued job on the host, not only the unit's. `isolate` applies only to
  a target with `AllowIsolate=yes` that you delegated.

Each grant is scoped three ways, and everything outside is refused:

- **Group.** Users outside it are refused.
- **Unit.** Units not in the resolved list are refused.
- **Verb.** Only the listed `actions` pass.
  - `kill`, `set-property`, `clean` and `bind-mount` are never granted: they
    change what a unit does or delete its state.
  - Freezing and thawing ask polkit for `stop` and `start`, but systemd's own
    D-Bus policy refuses them to unprivileged callers.

## `units` or `unitPrefixes`

| | `units` | `unitPrefixes` |
|---|---|---|
| Covers | Exactly the names you list | Every installed unit whose id starts with the prefix, recomputed at each rebuild |
| Risk | None beyond the list | Over-grants by construction: a unit added later with the prefix is included at the next rebuild, of any type (`.timer`, `.socket`, …) |
| Upkeep | A new or renamed unit needs a new entry | None |

Template instances (`foo@bar.service`) are not installed units, so a prefix
does not cover them. List each instance by name.

List canonical ids, not aliases: systemd always passes polkit the canonical
id, so an alias in the list never matches.

## Why enable and disable are never delegated

systemd asks polkit about enable, disable, mask, link and preset under a
different action, `org.freedesktop.systemd1.manage-unit-files`, and passes
**no unit name** with it. A rule cannot limit it to some units. Granting it
lets the group link a unit file it wrote, then start it as root. The relic
never grants it.

For an on-demand service, you do not need it: declare the unit without
`wantedBy` (`wantedBy = lib.mkForce []`) and delegate `start` and `stop`.

## How the rule is built

The relic generates one rule from `delegations` and writes it to
`security.polkit.extraConfig`:

- It acts only on `org.freedesktop.systemd1.manage-units`.
- It checks that polkit passed a unit and a verb before using them.
  - Manager-level calls (`systemctl reset-failed` with no unit, cancelling a
    job) pass neither.
  - Without that check, the rule throws, and polkit logs
    `TypeError: cannot read property 'indexOf' of undefined`.
- It returns `YES` or nothing; it never refuses. A `YES` ends polkit's
  evaluation, so it wins over a rule that polkit reads after it.

## With the hardening relics

The [filesystem hardening relic](/stc/en/relics/hardening/) mounts `/proc`
with `hidepid=2`, which breaks some tools that read other users' processes.
The delegation is not one of them. Polkit identifies the caller from D-Bus,
so the relic does not loosen any hardening setting.

## Proving

`provings/polkit-units.nix` boots a VM with one delegation and runs
`systemctl` as two unprivileged users. The delegation covers one unit by name,
one template instance and one prefix.

Granted to a member:

- restart, stop and start on the named unit;
- restart on a unit covered only by the prefix;
- start and stop on the listed instance.

Refused:

- another instance;
- another unit;
- another verb (`reload-or-restart`, `kill`);
- freeze and thaw, through `systemctl` and over D-Bus;
- `enable`;
- a user outside the group;
- a manager-level call with no unit;
- `systemd-run --unit=` under a name the prefix would have matched, and under
  the delegated names themselves.

Before the build-time resolution existed, the proving measured that
`systemd-run` under the prefix name ran as root.

Polkit logs no rule error. A positive control checks that its journal is the
one being read.

Every check runs a second time after `/proc` is remounted with
`hidepid=2,gid=proc`.
