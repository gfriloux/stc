## Feature Plan: a Nix store and journal housekeeping relic (#59)

**Type:** Architectural — new relic, a responsibility moved out of a cogitator
(`cogitator/nixos/vm.nix`), wired into five cogitators

**Goal:** A long-lived host built from STC bounds its Nix store and its journal
on its own: scheduled GC, GC under disk pressure during a build, store
deduplication on a timer, builds that yield to what the machine serves, a
journal cap.

**Why:** `cogitator/nixos/vm.nix` carries real GC configuration logic, which
DESIGN.md keeps out of profiles; the server profiles carry none of it, so a
docker-server host grows its store and journal without bound (#59).

### Measured premises (2026-10-24, locked nixpkgs `398fqjqk…-source`)

1. `services.journald.extraConfig` is removed (`mkRemovedOptionModule`,
   `systemd/journald.nix:40`); the relic writes
   `services.journald.settings.Journal.*`, a freeform `unitOption` submodule.
   No nixpkgs module writes `SystemMaxUse` or `MaxRetentionSec`.
2. `systemd.services.nix-gc` exists whenever `nix.enable` (`nix-gc.nix`), with
   no scheduling settings; `nix.gc.automatic` only adds `startAt` and the
   timer. Writing its `serviceConfig` is safe with the GC off.
3. `nix-optimise.service` is already `Nice=19`, CPU and IO `idle` upstream —
   nothing to add there.
4. `nix.daemonCPUSchedPolicy` / `daemonIOSchedClass` / `daemonIOSchedPriority`
   feed `nix-daemon`'s `serviceConfig` and propagate to builds. Upstream's own
   description says `idle` (CPU or IO) "may starve crucial configuration
   updates during load" and that systems other than intermittently loaded
   desktops "should use `other`/`batch`" and "`best-effort`".
5. Nothing upstream writes `nix-daemon`'s `OOMScoreAdjust`; `min-free` /
   `max-free` only in `profiles/nix-builder.nix` (not imported by STC).
6. Consumer `gfriloux/nixos` (`218ec9a`): no host enables `vm` or a server
   cogitator; `exampleHost` writes `nix.gc.*` / `nix.optimise.automatic`
   itself, at normal priority, on a workstation. No build impact.

### User decisions (2026-10-24)

- Scope: the issue's proposal, plus `OOMScoreAdjust = 250` on `nix-daemon` and
  batch/idle scheduling on `nix-gc`, under `deprioritiseBuilds`.
  Out of scope, by ruling: `nix.gc.randomizedDelaySec`, `--max-freed` GC mode.
- `mkDefault true` in docker-server, dreadnought, both sarcophagi and vm.

### Global Constraints

- Canonical namespace `stc.relics.nixHousekeeping`.
- `stc.cogitator.vm.nix.gc.{enable,dates,keepDays}` → `mkRenamedOptionModule`
  to `stc.relics.nixHousekeeping.gc.*`; vm keeps its 5-day window with
  `keepDays = mkDefault 5`, so the old option, forwarded at normal priority,
  still wins.
- Third-party options written with `mkDefault`, registered in the seal.
- `provings/vm.nix` "store growth is bounded" stays green **unchanged** — it is
  the proof the move preserves behaviour.

### Review Focus

- The rename: an old `stc.cogitator.vm.nix.gc.*` value must still land.
- Each new docker-server assert red on `nocrowdsec` (relic off).
- `deprioritiseBuilds` must not starve a `nixos-rebuild` on a loaded server.

### Affected Files

- `relics/nixos/nix-housekeeping.nix` (new), `relics/default.nix`
- `cogitator/nixos/{vm,docker-server,dreadnought,sarcophagus-aws,sarcophagus-kvm}.nix`
- `scripts/option-priorities.tsv`
- `provings/docker-server.nix`
- `docs/src/content/docs/{en,fr}/relics/nix-housekeeping.md` (new),
  `{en,fr}/relics/index.md`, the five cogitator pages (en+fr)

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: the relic, registered
#### Step 3: vm migrated (block removed, renames, keepDays 5); four server
cogitators wired; seal register updated
#### Step 4: proving — docker-server asserts on `machine`, counter-example on
`nocrowdsec`; `provings/vm.nix` untouched
#### Step 5: docs EN + FR

### Quality Gates

- `just ci` green (flake check, docs parity, option-priority seal).
- `just test` green; every new assert seen red against the relic-off node.
- Rename proven by eval: `stc.cogitator.vm.nix.gc.keepDays = 9` → `9d` in
  `nix.gc.options`, with a deprecation warning.
- `nix eval` of the three schematics' `drvPath`.
- Consumer `gfriloux/nixos`: three hosts evaluate with `--override-input stc`.
- Stale-reference grep (CLAUDE.md namespace checklist) over code and docs.
- One fresh-context review at branch close.
