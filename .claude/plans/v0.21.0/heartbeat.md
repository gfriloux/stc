## Feature Plan: heartbeat — success-only dead man's switch (#102)

**Type:** Architectural — new relic

**Goal:** `stc.relics.heartbeat.units.<unit>.urlFile` makes the unit ping a
consumer-owned URL each time it **succeeds**, and never otherwise, so the
receiver (Uptime Kuma push, healthchecks.io) alerts when the pings stop.

**Why:** every signal STC has detects a service answering badly now. Nothing
detects an absent event: a backup job that silently stops running reads as
"nothing to report" (#102, from gfriloux/nixos#87).

### User decisions (2026-10-25)

- Lot v0.21.0 = #101 then #102.

### Measured premises (2026-10-25, locked systemd and nixpkgs)

- NixOS exposes `systemd.services.<n>.onSuccess` (`systemd-unit-options.nix`).
- systemd.unit(5): `OnSuccess=` units are "activated when this unit enters the
  inactive state". A unit stopped while running (`systemctl stop`, shutdown)
  also ends inactive: `OnSuccess=` alone would turn "stopped" into "succeeded".
  *Corrected by measurement (Step 3): true for a long-running service, whose
  SIGTERM systemd counts as clean (`Result=success`); a oneshot stopped midway
  ends `Result=signal`, failed, and never triggers `OnSuccess=`.*
  So the heartbeat unit checks the observed unit's own outcome — `Result`,
  `ExecMainCode`, `ExecMainStatus` — before pinging. To be measured in the
  proving: a run stopped midway must not ping.

### Design

- Per observed unit `<n>`: `systemd.services.<n>.onSuccess =
  ["stc-heartbeat-<n>.service"]`, and a oneshot `stc-heartbeat-<n>`:
  - gate: `Result=success`, `ExecMainCode=exited`, `ExecMainStatus=0`;
  - the URL read through `LoadCredential` (DynamicUser, no root curl) and
    handed to curl on stdin (`-K -`), never on the command line, since the URL
    is the secret;
  - `curl --fail --retry 3 --max-time 10`; a failed ping fails the heartbeat
    unit, never the observed one (separate unit).
- Assertion: each named unit is a real service (has `script` or
  `ExecStart`). `systemd.services.<n>` always exists once the relic writes
  `onSuccess` into it, so existence alone proves nothing.

### Global Constraints

- Transport-agnostic: a URL, `*File` pattern; STC owns no receiver.
- Ping only on success; a ping never fails the observed unit.
- Containers' own jobs (no systemd unit per run) out of scope (issue).

### Review Focus

- Every way the observed unit can end inactive without having succeeded.
- The URL never reaches the store, a unit file or a process argv.

### Affected Files

- `relics/nixos/heartbeat.nix` (new), `relics/default.nix`
- `provings/heartbeat.nix` (new), `provings/default.nix`, `Justfile`
- `docs/src/content/docs/{en,fr}/relics/heartbeat.md` (new),
  `{en,fr}/relics/index.md`, `{en,fr}/provings/index.md`

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: the relic, registered
#### Step 3: proving — local HTTP stub: success pings, failure does not,
stopped midway does not, stub down leaves the observed unit successful, URL
absent from the unit files
#### Step 4: docs EN + FR

### Quality Gates

- `just ci`, `just test` green.
- `nix eval` of the three schematics' `drvPath`.
- Consumer `gfriloux/nixos`: three hosts evaluate with `--override-input`.
- One fresh-context review at branch close.
