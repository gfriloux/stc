# Ledger — plan: .claude/plans/v0.19.0/nix-housekeeping.md

Pre-flight: premises measured in the locked nixpkgs source and the consumer
repository before the plan was written.

Step 1: Ruling: **`nix-daemon` IO stays `best-effort`, at priority 7 — not
`idle`.** The lot plan said "daemon IO idle" (srvos' choice). Upstream's own
option description warns that `idle` may starve configuration updates under
load and tells servers to use `best-effort`; a docker host under steady IO
is exactly where a `nixos-rebuild switch` would stall. CPU goes to `batch`,
which upstream recommends for servers. `nix-gc` (not a configuration update)
does get CPU `batch`, IO `idle`. Cost if wrong: builds compete slightly more
with served IO than srvos would let them.

Step 1: Ruling: **every third-party write is `mkDefault`.** The relic's own
options are the knobs; `mkDefault` underneath means a consumer that writes
`nix.gc.options` or a journald key directly wins without `mkForce` instead of
hitting a conflict (`unitOption` and `str` both refuse two normal-priority
values). Same ruling as the survivability relic.

Step 2: Ruling: **optimise is skipped under `boot.isContainer`.** Found by the
seal's existing `allow` row, whose reason ("the vm cogitator is not a
container") stops holding once the relic is in four more profiles:
`container-config.nix` writes `nix.optimise.automatic = mkDefault false` there,
and a second `mkDefault true` is a conflict error. Measured by eval: vm with
`boot.isContainer = true` → `false`, no failed assertion. The allow row now
cites the guard.

Step 3: rename proven by eval on vm — default `--delete-older-than 5d`;
`stc.cogitator.vm.nix.gc.keepDays = 9` → `9d` with the rename warning;
`…gc.enable = false` → `automatic = false`; a consumer's direct
`nix.gc.options` / journald key wins over the relic. Seal: 23 files, 46
watched. vm count 1→2, servers +1, relic 14.

Step 4: the new docker-server subtest passed on its first run, so every value
it compares (`min-free = 5368709120`, `CPUSchedulingPolicy=3`,
`IOSchedulingClass=3`, `OOMScoreAdjust=250`, the journald keys, the timer and
`30d`) was seen equal on `machine` and different on `nocrowdsec` in the same
run — none can pass on stock defaults. `provings/vm.nix` untouched and green.

Step 5: Ruling: **`MIGRATION.md` left untouched.** It documents the one
`stc.*` → `stc.relics.*` migration; the vm rename is documented where a vm
user looks, on the vm cogitator page (EN + FR), next to its earlier
breaking-change note. Gates: `just ci` OK, three schematics evaluate
(local-vm renders `--delete-older-than 5d`), consumer hosts `warnings = []`
and drvPaths evaluate.

Closing review (fresh context): no Critical. **Important, taken:** with
`nix.enable = false` the relic made upstream's "nix.gc.automatic requires
nix.enable" assertion fire — a build break for a Nix-less appliance on four
profiles that built before. Store-side settings now sit behind `hasNix`, and
GC / min-free / optimise behind `ownsStore` (also `!boot.isContainer`: in a
container the store, its GC and its disk pressure are the host's — minor 5,
taken with the same guard). Measured by eval on vm: `nix.enable = false` → no
failed assertion, no stub `nix-gc` unit, journal cap kept; container → no GC,
no min-free, no optimise. Minors taken: `keepDays` back to `ints.unsigned` (the
old vm option was `int`; `0` would have become a type error through the
rename); `overridable-defaults.md` gains a v0.19.0 note on the two server
relics; doc notes on small disks and on `nh clean`'s overlap warning; proving
asserts the daemon's `IOSchedulingPriority` (7 vs stock 4) and names the node
on every failure.
