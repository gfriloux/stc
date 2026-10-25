# Ledger — plan: .claude/plans/v0.20.0/smart.md

Pre-flight: upstream `nixos/modules/services/monitoring/smartd.nix`, the
smartmontools package and its man pages read on the locked nixpkgs; QEMU SATA
SMART measured by a spike test.

Step 1: Ruling: **`STC_SMART_FAILTYPE` added** beside the issue's three
variables. It is what tells a `-M test` message (`EmailTest`) from a real
`Health` or `Temperature` alert, so a consumer can route or silence it.
Cost if wrong: one variable nobody reads.

Step 1: Ruling: **`STC_SMART_DEVICE` carries `SMARTD_DEVICESTRING`**, not
`SMARTD_DEVICE`: on a disk behind a RAID or USB bridge, the string names the
real target (`/dev/sda [SAT]`, `/dev/bus/0 [megaraid_disk_00]`).

Step 1: Ruling: **savestates on, under `/var/lib/smartmontools`.** Without
them smartd re-sends every standing warning after each reboot and forgets the
next self-test due. Declared `cache` in the manifest: losing it costs one
duplicate warning, not data.

Step 1: Ruling: **no `-q never`.** A smartd with no device to watch fails its
unit. Documented as the cloud caveat, proven on `virtonly`.

Step 2: `relics/nixos/smart.nix`, registered as `relics-smart`. Two
assertions measured by `nix-instantiate --eval --arg extra`: empty
`notifyCommand` → fails; `services.smartd.notifications.wall.enable = true`
→ fails; with a command and defaults → `[]`; plain `services.smartd` without
the relic → `[]`. Seal: `count` 3/0/0 plus three `watch` rows; `just ci`
reports 24 files, 49 options.

Step 2: Ruling: **`overridable-defaults.md` unchanged.** Its tables record
what became overridable in a release; the three smartd channels are defaults
only so that the assertion, not a bare conflict, answers a consumer who turns
one back on. The seal rows carry the reason.

Step 3: `provings/smart.nix`, in the registry and the `test` recipe. Green on
the first run. The alerts are smartd's own: `EmailTest` (`-M test`) and a
real `Temperature` alert (QEMU reports 31 °C, the node's critical limit is
30 °C), both with `/dev/sda [SAT]`, the hostname and the message. Tightened
after the first run: the state file is named
(`smartd.QEMU_HARDDISK-STCSMART0.ata.state`) instead of a restart that proved
nothing more, and `virtonly`'s failure is pinned to exit status 17 (smartd's
"no device"), not any failure.

Step 4: `relics/smart.md` EN + FR (options, directive table, environment,
cloud caveat, state, proving), relics index row and link, state-manifest
table row. FAILTYPE values checked against smartd.conf(5).

Gates: proving rc=0, `just ci` rc=0, local-vm / aws-ami / dreadnought rc=0,
consumer warnings `[]` on clochette, RogueLeader, exampleHost.

Closing review (fresh context): no Critical. Important, all taken:
- I1 `provings/index.md` stale: now twelve provings, eighteen boots (the
  count had also missed `docker-server`'s second node), a `smart` coverage
  row, "ten of the twelve" synthesise a node. EN + FR.
- I2 smartd blocks on `-M exec` and reads output as trouble: notifyCommand
  now runs from its own script under `timeout notifyTimeoutSec` (new option,
  60 s), output sent to the journal by `systemd-cat -t stc-smart-notify <cmd>`
  (a pipe into `systemd-cat` failed in the proving: with no command it execs
  `/bin/cat`, absent on NixOS — smartd logged "Failed to execute process"); the
  example gains `--max-time 10`. Proven: the journal carries the command's
  output.
- I3 savestates turns the reminder default to `-M daily`. Ruling: kept and
  documented (module comment, docs); `-M once`/`diminishing` named as the
  way out.
Minor taken: a consumer `-M exec` anywhere smartd reads is now an assertion
(seven eval cases measured: relic alone, in `defaults`, in `autodetected`,
plain `autodetected`, in a device, plain device, in `monitored`);
`STC_SMART_DEVICE == "/dev/sda [SAT]"` asserted exactly; the docs say
`notifications.test` does nothing here; the proving notes that `virtonly`'s
exit 17 also proves the default `defaults` parses.
Minor not taken: the conf subtest stays as a regression guard though eval
catches it first; `hostname` keeps `networking.hostName` for parity with
docker/notify.
