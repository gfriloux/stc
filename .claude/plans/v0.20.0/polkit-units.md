## Feature Plan: polkit unit delegation (#63)

**Type:** Architectural — new relic, security-relevant (widens privileges)

**Goal:** `stc.relics.polkitUnits.delegations` lets a group start, stop or
restart named units without `sudo`, through one generated polkit rule that
grants nothing else.

**Why:** `sudo systemctl` is all-or-nothing; the need is "restart this one
container". A hand-written polkit rule is easy to get wrong (#63).

### User decisions

- 2026-10-24: default verbs are start/stop/restart; nothing broader by default.
- 2026-10-25: **no `allowEnable`**. Measured below: enable/disable cannot be
  scoped to a unit, so delegating them is root by another name.

### Measured premises (2026-10-25, locked nixpkgs: systemd source, polkit 127)

- `org.freedesktop.systemd1.manage-units` carries the details `unit` (the
  full id, `foo.service`) and `verb` (`src/core/dbus-util.c`). Job verbs:
  `start`, `stop`, `restart`, `try-restart`, `reload`, `reload-or-restart`,
  `reload-or-try-restart`. Other verbs under the same action: `kill`,
  `kill-subgroup`, `reset-failed`, `set-property`, `ref`, `clean`, `freeze`,
  `thaw`, `bind-mount`, `mount-image`.
- Manager-level calls (`CancelJob`, `ResetFailed` with no unit,
  `EnqueueMarkedJobs`) ask for `manage-units` with **no details**: the rule
  must test `unit` and `verb` before using them.
- Enable, disable, mask, link and preset go through
  `org.freedesktop.systemd1.manage-unit-files`, with **no details at all**
  (`bus_verify_manage_unit_files_async`). It cannot be limited to a unit;
  granting it lets the group `systemctl link` a unit file it wrote and run
  it as root.
- `security.polkit.enable` is off on a minimal NixOS: without it every
  request is denied, the rule unused. Spike: same rule denied everything until
  polkit was enabled.
- Spike (test VM, locked nixpkgs): a rule scoped to group + unit + verbs
  grants `restart`/`stop`/`start` on the named unit, and denies another unit,
  another verb (`reload-or-restart`, `kill`) and `enable`. Identical after
  `mount -o remount,hidepid=2,gid=proc /proc`: polkit gets the caller from
  D-Bus credentials, so the hardening relic's hidepid does not break it, and
  the relic needs nothing from the `proc` group.

### Options

```nix
stc.relics.polkitUnits = {
  enable;
  delegations = [{
    group;                       # must exist in users.groups
    units = [];                  # exact names; ".service" added when no suffix
    unitPrefixes = [];           # over-grants by construction; documented
    actions = ["start" "stop" "restart"];   # job verbs only
  }];
};
```

### Global Constraints

- Default grants nothing: `delegations = []`.
- One rule block, generated from data; it returns YES or nothing, never NO,
  so it cannot override another rule's decision.
- No `manage-unit-files`, no non-job verbs.
- Nothing in `relics/nixos/hardening/*` changes.

### Review Focus

- Every path in the generated JavaScript when `unit` or `verb` is absent.
- Prefix matching cannot be widened to "everything" (empty prefix).
- Template units under a prefix: the instance name is caller-chosen.

### Affected Files

- `relics/nixos/polkit-units.nix` (new), `relics/default.nix`
- `provings/polkit-units.nix` (new), `provings/default.nix`, `Justfile`
- `docs/src/content/docs/{en,fr}/relics/polkit-units.md` (new),
  `{en,fr}/relics/index.md`, `{en,fr}/provings/index.md`

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: the relic, registered
#### Step 3: proving — a member, a non-member, a named unit, a prefixed unit,
an undelegated unit, an undelegated verb, `enable`, a manager-level call with
no unit; repeated under hidepid=2
#### Step 4: docs EN + FR

### Quality Gates

- `just ci` green.
- `just test` green, with the new proving in the recipe.
- `nix eval` of the three schematics' `drvPath`.
- Consumer `gfriloux/nixos`: three hosts evaluate with `--override-input`.
- One fresh-context review at branch close.
