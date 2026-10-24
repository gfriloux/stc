## Feature Plan: a headless-survivability relic (#69)

**Type:** Architectural — new relic, wired into four cogitators

**Goal:** A server built from STC reboots itself instead of waiting for a human
who is not there: no emergency shell, reboot on panic, a hardware watchdog,
a bounded `/boot`, no suspend.

**Why:** The four server profiles (`docker-server`, `dreadnought`,
`sarcophagus-aws`, `sarcophagus-kvm`) inherit stock NixOS defaults tuned for a
machine with someone in front of it. On a remote host, each of them turns a
recoverable fault into a dead machine (table in #69).

### Measured premises (2026-10-24, locked nixpkgs)

1. `systemd.settings.Manager`, `systemd.sleep.settings.Sleep` and
   `systemd.enableEmergencyMode` exist. No schematic sets any watchdog key.
2. `enableEmergencyMode = false` drops `emergency.{target,service}` from
   **stage 2 only** (`emergency-mode.nix:34`). The initrd's unit list is a
   hard-coded `upstreamUnits` in `systemd/initrd.nix:55-70` that contains
   `emergency.target`, so `stc.relics.impermanence.onRollbackFailure =
   "emergency"` keeps its target. Checked by eval on dreadnought with
   `onRollbackFailure = "emergency"`: `OnFailure = emergency.target` both ways.
   → no collision, no assertion needed. **Superseded at the closing review:**
   `boot.panic_on_fail` makes that target crash the kernel — see the ledger
   (assertion, user ruling).
3. Probe VMs (`runNixOSTest`, bare node vs configured node):
   - the test VM **already has a hardware watchdog** (`iTCO_wdt`, q35) —
     no `-device i6300esb` needed. Bare: `RuntimeWatchdogUSec=0`, no journal
     line. Configured: `Using hardware watchdog /dev/watchdog0: 'iTCO_wdt'` and
     `Watchdog running with a hardware timeout of 30s`;
   - `RebootWatchdogUSec=10min` on the **bare** node — systemd's own default.
     Setting it would be a no-op;
   - the test harness already puts `panic=1 boot.panic_on_fail` on the cmdline.
     Only `panic=30` discriminates; it comes later on the cmdline and wins
     (`/proc/sys/kernel/panic`: 1 bare, 30 configured);
   - `[Sleep]` is empty bare, `AllowSuspend=no` / `AllowHibernation=no`
     configured.
4. `relics/nixos/hardening/kernel.nix:61` sets the sysctl `kernel.panic = 30` at
   normal priority. The relic must not write that sysctl (conflict when both are
   on).
5. `profiles/headless.nix` disables `serial-getty@ttyS0` and adds
   `nomodeset`/`vga=0x317` — wrong for a VPS whose only out-of-band access is
   the serial console.

### User decisions (2026-10-24)

- `mkDefault true` in all four server cogitators.
- Watchdog on by default, `RuntimeWatchdogSec = "30s"`, own sub-option.

### Global Constraints

- Canonical namespace `stc.relics.serverSurvivability`; no alias.
- Every sub-behaviour is individually switchable; third-party options the relic
  writes with `mkDefault` are registered in `scripts/option-priorities.tsv`.
- No build breaks for any consumer; the three schematics keep evaluating.

### Review Focus

- Each proving assert must be red on a node with the relic off.
- The module comment must say why `profiles/headless.nix` is not imported.

### Affected Files

- `relics/nixos/server-survivability.nix` (new), `relics/default.nix`
- `cogitator/nixos/{docker-server,dreadnought,sarcophagus-aws,sarcophagus-kvm}.nix`
- `provings/docker-server.nix`
- `scripts/option-priorities.tsv`
- `docs/src/content/docs/{en,fr}/relics/server-survivability.md` (new),
  `{en,fr}/relics/index.md`, the four cogitator pages (en+fr)

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: the relic, registered
#### Step 3: wired into the four cogitators, seal register updated
#### Step 4: proving — asserts on `machine`, counter-example on `nocrowdsec`
(relic forced off there)
#### Step 5: docs EN + FR

### Quality Gates

- `just ci` green (flake check, docs parity, option-priority seal).
- `just test` green; every new assert seen red against the relic-off node.
- `nix eval` of the three schematics' `drvPath`.
- Consumer `gfriloux/nixos`: three hosts evaluate with `--override-input stc`.
- One fresh-context review at branch close.
