## Feature Plan: SMART disk monitoring, transport-agnostic (#60)

**Type:** Architectural — new relic

**Goal:** `stc.relics.smart.enable = true` runs smartd over every SMART-capable
disk and hands each alert to a consumer-supplied `notifyCommand`, the way
`relics/nixos/docker/notify.nix` already does for containers.

**Why:** `zfs.nix` sees a pool once a disk has failed; SMART sees reallocated
sectors, pending sectors and temperature before that. `services.smartd`
appears nowhere in the repository (#60).

### User decisions (2026-10-24)

- No cogitator wiring: the relic is opt-in only. Cloud disks have no SMART,
  and a profile cannot know whether its host has real disks.
- `notifyCommand` is asserted non-empty when enabled, like docker/notify.

### Measured premises (2026-10-25)

- Upstream `services.smartd` (locked nixpkgs) builds `smartd.conf` as
  `DEFAULT <notifyOpts><defaults.monitored>` + device lines +
  `DEVICESCAN <notifyOpts><defaults.autodetected>`. `notifyOpts` is
  `-m <nomailer> -M exec <its script>` as soon as mail, wall or x11 is on —
  and wall defaults to **true**. Writing our own `-M exec` on top would give
  smartd two exec directives, so the relic turns the three upstream channels
  off (mkDefault) and asserts they stay off.
- smartd's exec environment carries `SMARTD_DEVICE`, `SMARTD_DEVICESTRING`,
  `SMARTD_FAILTYPE`, `SMARTD_MESSAGE`, `SMARTD_FULLMESSAGE` (smartd.conf(5)).
- smartmontools 7.5 in nixpkgs is built without a savestates default, so
  smartd keeps no state across restarts unless `--savestates=PREFIX` is
  passed. Without it, every restart forgets the last warning sent and the
  next self-test due. `-S on` in the issue's defaults is the **drive's**
  attribute autosave, not a file.
- smartd with no SMART-capable device exits (`-q nodev`, the default): the
  unit fails. On a cloud VM, an enabled relic shows as a failed unit. Kept:
  a smartd that monitors nothing and reports active would read as coverage.
- A QEMU SATA disk (`-blockdev driver=null-co` + `-device ide-hd` on the
  test VM's q35 AHCI bus) answers SMART: health PASSED, attributes, and
  temperature 31 °C. Spike run on the locked nixpkgs. So a proving can drive
  a real alert end to end.

### Options

```nix
stc.relics.smart = {
  enable;
  autodetect = true;            # DEVICESCAN; false = services.smartd.devices only
  defaults = "-a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,45,55";
  hostname = networking.hostName;
  notifyCommand = "";           # asserted non-empty
};
```

The wrapper exports `STC_SMART_DEVICE` (`SMARTD_DEVICESTRING`),
`STC_SMART_MESSAGE`, `STC_SMART_FAILTYPE`, `STC_SMART_HOSTNAME`, then runs
`notifyCommand`.

### Global Constraints

- Transport-agnostic: no mail, ntfy or webhook option in STC.
- Upstream notification channels off at mkDefault, asserted off: one alert
  path, and a clear message rather than a duplicate `-M exec`.
- State under `/var/lib/smartmontools` (`StateDirectory`), declared in the
  state manifest as `cache`.
- Every mkDefault on a third-party option gets its seal rows.

### Review Focus

- The generated `smartd.conf`: one `-M exec`, ours, on DEFAULT and
  DEVICESCAN.
- The proving's alert is a real one smartd raised, not a hand-run wrapper.

### Affected Files

- `relics/nixos/smart.nix` (new), `relics/default.nix`
- `scripts/option-priorities.tsv`
- `provings/smart.nix` (new), `provings/default.nix`, `Justfile`
- `docs/src/content/docs/{en,fr}/relics/smart.md` (new),
  `{en,fr}/relics/index.md`, `{en,fr}/reference/state-manifest.md`,
  `{en,fr}/reference/overridable-defaults.md` if it lists per-relic defaults

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: the relic, registered, seal rows
#### Step 3: proving — `machine` (relic on, SATA disk, `-M test` and a
critical temperature below the emulated 31 °C) records the wrapper's
environment; `virtonly` (relic on, virtio disk only) shows smartd failed
#### Step 4: docs EN + FR

### Quality Gates

- `just ci` green (seal included).
- `just test` green, with the new proving in the recipe.
- `nix eval` of the three schematics' `drvPath`.
- Consumer `gfriloux/nixos`: three hosts evaluate with `--override-input`.
- One fresh-context review at branch close.
