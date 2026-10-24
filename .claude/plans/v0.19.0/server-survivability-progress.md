# Ledger — plan: .claude/plans/v0.19.0/server-survivability.md

Pre-flight: the premises were measured before the plan was written — option
paths by eval, the initrd/stage-2 split by eval and source, and the runtime
behaviour on three probe VMs (bare, configured, configured + i6300esb).

Step 1: Ruling: **no `RebootWatchdogSec`.** The approved lot plan said to set it
to `"10min"`; the bare probe node already reports `RebootWatchdogUSec=10min`,
systemd's default. Writing it would change nothing and a proving assert on it
would be a tautology. Cost if wrong: none at runtime; the docs say the default
applies.

Step 1: Ruling: **no `-device i6300esb` in the proving.** The q35 test machine
exposes `iTCO_wdt` already; systemd opens `/dev/watchdog0` with it. Cost if
wrong: none — the assert reads systemd's own journal line, whichever driver.

Step 1: Ruling: **the cmdline carries `panic=30`, not `panic=1`.** Same value as
the hardening relic's sysctl, so the timeout does not change when
`systemd-sysctl` runs. The relic never writes the sysctl itself (it would
conflict at normal priority with `relics/nixos/hardening/kernel.nix`). Cost if
wrong: 29 extra seconds before a panicked host reboots.

Step 1: Ruling: **`boot.panic_on_fail` is set, but never asserted** — the test
harness puts it on every test VM's cmdline, so its presence proves nothing.
Same for `panic=1`.

Step 1: Ruling: **no assertion against `onRollbackFailure = "emergency"`.**
Measured: the initrd keeps `emergency.target` whatever `enableEmergencyMode`
says; the two settings act on different stages.

Step 1: Ruling: **no `KExecWatchdogSec`.** STC's hardening disables kexec
(`kernel.kexec_load_disabled`), and no profile kexecs.

Step 2: Ruling: option names follow the house style of single-level booleans
(`disableEmergencyMode`, `panicReboot`, `forbidSleep`) rather than the
`emergencyMode.disable` sketched in the lot plan; only the watchdog, which has
a value of its own, is a sub-attrset.

Step 3: the seal accepted the three new `watch` rows with no `allow` — no
upstream module writes `systemd.enableEmergencyMode` or either
`configurationLimit` with `mkDefault`. Counts: docker-server 4→5,
dreadnought/sarcophagi 2→3, relic 3.

Step 4: Ruling: no third proving node. `nocrowdsec` gets
`serverSurvivability.enable = false` and every assert is written
`(observed) == on` over both nodes, so each one is seen true on `machine` and
false on `nocrowdsec` in the same run — the red side is not a separate,
forgettable step. The generation cap is asserted on the evaluated configs (a
test VM has no bootloader); the off node shows GRUB's own default.

Step 4: **finding** — `systemctl cat emergency.service; echo $?` printed nothing
on the probe node with emergency mode off (the shell line itself returned no
output). `systemctl show -p LoadState --value` gives `not-found` / `loaded`
cleanly and is what the proving uses.

Step 5: `reference/overridable-defaults.md` left untouched: it is the v0.18.0
audit's record, not a per-relic list of defaults, and the new page states its
own `mkDefault`s.

Closing review: **Important — my Step 1 ruling on impermanence was wrong.** I
had checked that the initrd keeps `emergency.target`, not what that target
pulls in: `boot.panic_on_fail` arms the initrd's `panic-on-fail.service`
(`wantedBy = ["emergency.target"]`, `systemd/initrd.nix:840-853`), which
crashes the kernel — so `onRollbackFailure = "emergency"` plus `panic=30`
reboots every 30 s instead of stopping. Verified in source before acting.
**User ruling: assertion** (over "impermanence wins" and "document the loop").
Measured by eval on dreadnought: fires only for emergency + panicReboot; clean
for the default, for `panicReboot = false`, and for the relic off. The
`emergencyvariant` node of `provings/dreadnought.nix` now sets
`panicReboot = false` — the documented path. No consumer sets
`onRollbackFailure`. Cost if wrong: a build error with both remedies named.

Closing review, minors taken: `RuntimeWatchdogSec` and both `Sleep` keys
demoted to `mkDefault` (they are `unitOption`, `mergeEqualOption`, so a
consumer's own value was a conflict error) — seal count 3→6, three `watch`
rows, no upstream collision; "unbounded /boot" corrected (GRUB defaults to
100, systemd-boot is unbounded); cloud-image `panic=1` stacking noted in the
docs; the `panic=30` assert commented as presence-not-effect; hardening page
tells a server operator to also set `panicReboot = false` for a frozen
post-mortem machine.
