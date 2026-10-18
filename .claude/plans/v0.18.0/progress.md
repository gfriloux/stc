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

Step 2: Ruling: innocuousness is measured on **14 witnesses**, not the 3 the plan
names. The three schematics do not import `enginseer`, `desktop`, `plasma`,
`gaming` or `vm`, so for those files a schematic `drvPath` proves nothing. The
battery is the 3 schematics plus the 11 provings, recorded before and after the
whole set of edits. Result: **14/14 byte-identical** — cost if wrong: none, this
is strictly more coverage than the plan asked for.

Step 2: Ruling: `relics/nixos/zfs.nix` and `relics/nixos/boot.nix` share one
commit instead of one each, against the plan's "one commit per file". Both are
single-line relic defaults with the same argument (a safe default a consumer
could not express otherwise) and separate commits would have been noise — cost if
wrong: a slightly coarser revert.

Step 2: Two of my first usefulness witnesses did not discriminate, and I nearly
recorded them as proof: `services.pipewire.enable` and
`hardware.graphics.enable32Bit` stay true with the relic declined, because
nixpkgs' plasma6 module and `programs.steam` set them on their own. Replaced with
the STC option itself plus `security.rtkit.enable`, which only the Pipewire relic
writes — measured true on the baseline and false with the relic declined. This is
the repository's named error profile repeating.

Step 2: complete — 45 demotions across 18 files, 17 commits (798c1d6..HEAD).
Usefulness proved per class with *plain* definitions: pipewire off under plasma,
amdGpu off under gaming, scheduler off under the hardening suite,
AllowAgentForwarding on, canTouchEfiVariables off, kitty off under desktop, and
five Home Manager settings. Best control of the lot: with no CrowdSec image
supplied, declining the relic evaluates while *not* declining it fails on
"crowdsec.enable is true but no image is set" — so the fix is exactly what the
triage claimed.

Step 3: complete — `provings/plasma.nix` gains a second node carrying a plain
`stc.relics.pipewire.enable = false`. The plainness is the proof: that node could
not have been built before this chantier. Assertions chosen to discriminate
(rtkit absent, no `libs.32Bit` in the ALSA config, session untouched) because the
Pipewire units themselves come from nixpkgs' plasma6 module. The VM log is the
nicest evidence: `pipewire: mod.rt: RTKit error: ServiceUnknown` — Pipewire runs,
STC's relic is gone.

Step 3: `just test` green, exit 0. Honest note: only the plasma proving actually
re-ran; the other ten were cache hits, which is exactly what the witness identity
predicted — unchanged `drvPath` means unchanged test.

Step 4: Ruling: the per-option documentation is **one reference page plus four
targeted call-outs**, not a paragraph appended to all sixteen affected pages. The
plan asked for "per demoted option, on the relic's own page" — sixteen pages × two
languages of near-identical boilerplate would age into drift, and the sidebar
autogenerates the reference section so the page is discoverable. The call-outs go
where the demotion changes what a reader can *do*: the hardening cogitator (six
sub-relics), docker-server (the image trap), desktop (one terminal instead of
two), and the hardening relics (the three sshd switches plus coredumps).
Enginseer keeps its own detailed treatment because its documentation was false.
Cost if wrong: a reader of, say, the zfs relic page finds the escape hatch one
link away instead of in place.

Step 4: complete — `docs/{en,fr}/reference/overridable-defaults.md` carries the
rule, the full list of what became overridable with the version, **and what stays
pinned with its reason** (the second half matters more: it is what keeps the page
from reading as a backlog). `just ci` green, docs build 92 pages.

## Closing review — what it found, and what I verified before acting

The review ran twice (unscoped, then on the branch) and the two passes
**contradicted each other**, so every finding was re-measured here rather than
implemented on trust. Two were right about something being *wrong* rather than
incomplete; one was itself wrong.

Review: Ruling: **the coredump safety claim I published is false, and it is
corrected rather than defended.** `relics/nixos/hardening/kernel.nix` and both
hardening doc pages said re-enabling `systemd.coredump` is safe because the
relic's PAM limit stays in place. Refuted two independent ways: `loginLimits`
writes `/etc/security/limits.conf`, applied by `pam_limits` to PAM login sessions
only, so it never bounded a daemon; and `core(5)`, read from the pinned
man-pages, says verbatim *"The RLIMIT_CORE limit is not enforced for core dumps
that are piped to a program"* — and enabling systemd-coredump is what installs a
pipe `core_pattern`. The demotion stays (an operator must be able to), the
reassurance is replaced by the real consequence: daemons dump full address space,
secrets included, to `/var/lib/systemd/coredump`. Fourth false fact I have
published in a doc page across these chantiers; the pattern is naming a mechanism
I have not measured.

Review: Ruling: **the `X11Forwarding` demotion was a regression and is replaced
by options, not reverted.** Measured on both refs: a node with
`stc.cogitator.hardening.enable` and `services.slurm.client.enable` evaluates on
`main` (`X11Forwarding = false`) and **fails on the branch**, because
`slurm.nix:491` writes `X11Forwarding = mkIf cfg.client.enable (mkDefault true)`
and two `mkDefault`s disagree. This inverts the first item of the plan's *Review
Focus*: I predicted demotion would let a consumer win silently, and the real
hazard is demotion *introducing* a conflict where a normal-priority pin used to
win quietly. Fix: `allowedX11Forwarding`, `allowedAgentForwarding` and
`allowedTunnel`, written at normal priority from the option, matching the
`allowedTCPForwarding` two lines away. Measured after: the Slurm composition
evaluates again with the same value as `main`, defaults unchanged, all three
options honoured. Cost if wrong: three options in a namespace that already had
the pattern.

Review: Ruling: **one reviewer finding is wrong and is not implemented.** It
claimed demoting `services.udisks2.enable` creates a new conflict with
`budgie.nix:269` (`mkDefault true`). It does not: budgie also writes
`services.gvfs.enable = mkDefault true`, and `gvfs.nix:51` writes
`services.udisks2.enable = true` at **normal priority**, which masks both
`mkDefault`s. The other review pass had measured this correctly and said so. Two
reviewers, opposite conclusions, and the source settles it.

Review: Ruling: **a claim made by the review itself was false.** One pass
reported it had swept nixpkgs, home-manager, catppuccin and impermanence for
competing `mkDefault` definitions of every demoted option and that "none exist".
Slurm exists, and the other pass found it. A reviewer's verification claim is
evidence, not proof — same lesson as v0.15.0, where a reviewer's proposed
correction was itself wrong.

Review: the audit's inventory had a **structural blind spot**: the grep matched
`= (true|false);`, so it never saw `mkForce` definitions — a strictly stronger
pin than the one the issue was about — nor non-boolean assignments. 26 `mkForce`
occurrences exist in `relics/` and `cogitator/`; one of them
(`cogitator/home/desktop.nix`) was measured to silently discard a consumer's own
`pinentry` choice, which is worse than the conflicts this chantier removed.
Fixed here with `lib.mkOverride 900` (beats enginseer's `mkDefault`, loses to a
consumer's definition) and locked in by a third node in
`provings/home-desktop.nix`. The remaining 25 are handled by chantier B's
register rather than a second audit.

Review: fixed without argument, each verified: the `forceImportAll` doc row
omitted upstream's `forceImportAll -> forceImportRoot` assertion; the `udisks2`
row ignored that `amazon-image.nix:139` pins the option at normal priority on the
AWS path; the `canTouchEfiVariables` row was contradicted by the two sarcophagi,
which `mkForce`d it (now a plain `false`, so the relic's `mkDefault` is still
beaten but the consumer is not); declining the socket proxy makes the Traefik
relic bind-mount `/run/docker.sock` read-only (`traefik.nix:391`), which the new
doc section presented as free; the CrowdSec-without-an-image claim had no
proving (now `nodes.nocrowdsec`, deliberately given no image); and the plasma
node's `succeed("cat .../49-pipewire-modules.conf")` coupled the proving to an
upstream `alsa.enable` STC does not own (now tolerant of the file's absence).

Review: deviation, recorded rather than rewritten: the three corrected rows of
`reference/overridable-defaults.md` (zfs, udisks2, EFI) rode along in the sshd
commit instead of getting their own, because both touched the same two files and
I staged them together. The planned fifth commit was therefore empty. Four signed
commits would have had to be rebased and re-signed to fix the attribution — not
worth it for an atomicity miss that makes no claim false. Cost if wrong: one
commit message under-describes its diff.

Review: `just test` green on the final tree (exit 0), and the `nocrowdsec` node
demonstrably booted. Honest limit on that evidence: the background log was
captured through `tail`, so the subtest lines themselves are not in it — the
proof is `nix build`'s exit status plus the node's boot, not a printed assertion.
