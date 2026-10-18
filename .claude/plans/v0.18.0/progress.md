# Ledger — plan: .claude/plans/v0.18.0/plan.md

Pre-flight: the plan's two measurable verification commands were run before being
written into it — the inventory grep (→ 141) and the dreadnought `drvPath`
(`system.build.toplevel.drvPath`, which `CLAUDE.md` does not list). A third claim
was removed instead of kept: "15 boots" came from memory, not a measurement, so
the plan now cites only `grep -c "nix build .#legacyPackages" Justfile` → 11.

Pre-flight: Ruling: the issue's "104 candidates" is not reproducible — a strict
grep gives 167, and 141 after removing `default =` / `example =` rows inside
`mkOption` blocks. 141 is the inventory of record; the delta is written into the
triage rather than silently adopted — cost if wrong: the sort covers more lines
than asked, never fewer.

Step 1: Ruling: bulk-reading `highestPrio` by walking `options` is abandoned. It
was the first approach and it cannot be made defensive: forcing `isDefined` on a
submodule option evaluates upstream defaults, and `hardware.nvidia.open` →
`nvidia_x11.version` on `null` is a *type* error, which `tryEval` does not catch
(confirmed with `--show-trace`). Inventory therefore comes from the source, and
priority is measured per option on the paths STC actually writes — cost if wrong:
none, the per-option measurement is strictly more reliable, only slower.

Step 1: Ruling: no per-row measurement. Six override attempts conflicted 6/6, and
two `mkForce` controls evaluated, which establishes non-overridability as a
property of the module system rather than of any file. Each row therefore needs a
*verdict*, not a measurement — measurements are spent on the verdicts that are
not obvious — cost if wrong: a row classified as a defect that was already
overridable, caught in step 2 by the `drvPath` identity check.

Step 1: Ruling: **the plan's sorting rule was wrong and is replaced.** The plan
proposed "activating is the relic's trade, configuring is a preference". First
real case broke it: `cogitator-dreadnought` enables `stc.relics.zfs` *and*
declares `fileSystems."/"` with `fsType = "zfs"`. Measured — with
`stc.relics.zfs.enable = lib.mkForce false` the configuration still evaluates and
yields a host whose root is ZFS on a system without ZFS. The normal priority is
what turns that into a build error today. New rule, written at the top of the
triage: a normal-priority definition is legitimate when the conflict it raises is
the only thing stopping an incoherent configuration from evaluating, and a defect
when switching it off leaves the profile coherent. Cost if wrong: a relic
enablement left pinned that a consumer wanted to compose away — one commit each.

Step 1: Bench defect caught by its own baseline: the first `cogitator-gaming`
probe failed and I nearly recorded "gaming requires amdGpu". Cause was Steam's
unfree licence, and I had not built the baseline first. `allowUnfree` added, both
cases remeasured, both additive. This is the v0.16.0 lesson (build the reference
node first) repeating.

Step 1: Ruling: `services.udisks2.enable = false` (AWS relic) is demoted to
`mkDefault` rather than deleted, even though upstream already defaults it to
`false` (measured, bare node and option default). Deletion is defensible but
erases a documented intent ("udisks2 pulls in GTK — not acceptable on a headless
server"); `mkForce` would deliver the intent while silently breaking a consumer's
desktop. Demotion plus an honest comment keeps the intent readable and the
consumer in charge — cost if wrong: one line.

Step 1: complete — 141 rows sorted: **45 boolean defects**, 3 named non-boolean
defects, 93 legitimate, 3 false positives (`assertion = false` rows inside
`assertions`, which the grep could not distinguish).

Step 1: minor (deferred, not fixed): `relics/nixos/plasma6.nix` claims in a
comment that "the GTK portal provides a fallback for non-KDE applications" while
`xdg.portal.extraPortals = []` installs no such portal. A false statement in a
comment, unrelated to priority — recorded in the triage, worth its own issue.
