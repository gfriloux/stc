## Maintenance Plan: Audit of options pinned at normal priority

**Type:** Refactor moving a responsibility boundary (what a relic owns vs what the
consumer keeps) — [issue #86](https://github.com/gfriloux/stc/issues/86)

**Goal:** Sort every definition STC writes at normal priority into *defect* or
*legitimate*, write the verdict down, and demote only the defects to
`lib.mkDefault` with proof that no default-path consumer changes.

**Why:** Five occurrences of the same defect have been found, each by accident,
each while doing something else. A relic pins an upstream (or STC) option at
normal priority while its own documentation presents the value as overridable, or
while the override is a legitimate need. The consumer gets
`has conflicting definition values` — or worse, an unrelated upstream assertion —
and nothing tells them the option is not overridable. The `plasma6` case survived
since `v0.1.0`, contradicting the relic's own public option, because no test took
that path.

**Architecture:** No new relic, no new option, no namespace change. What moves is
a boundary inside `DESIGN.md`: for each line, does the relic *own* that value
(its job, and weakening it would make the relic pointless), or does it merely
*propose* one (and the consumer must be able to say otherwise)? The sort is the
deliverable; the `mkDefault` edits are its consequence.

### Measured premises

Everything below was measured on the locked nixpkgs **before** this plan was
written. Each line is a fact the steps depend on.

| Premise | Measured | Consequence for this plan |
|---|---|---|
| Candidate count | **141** boolean definitions at normal priority in `relics/` + `cogitator/` (167 before removing `default =` / `example =` lines inside `mkOption` blocks), of which **26** target an `stc.*` option | The issue says 104. That number is not reproducible with a stricter grep and is **not** used as the target; 141 is the inventory, and the delta is itself recorded in the triage |
| Reading the effective priority by walking `options` recursively | **Unusable.** `highestPrio` and `definitionsWithLocations` exist per option, but reaching them forces `isDefined`, which on a submodule option evaluates upstream defaults — `hardware.nvidia.open` → `nvidia_x11.version` on `null`. That is a *type* error, which `tryEval` does **not** catch, so the walk cannot be made defensive | The inventory comes from the source (grep), and the priority is measured one option at a time, only on paths STC actually writes |
| The measurement that decides a candidate | Evaluating a consumer that sets the opposite value at normal priority. Conflict → the STC definition is at normal priority. No conflict → already overridable | This is the per-candidate verification command of step 2 |
| Third known case, `cogitator/nixos/plasma.nix:27` | **Confirmed.** With `stc.cogitator.plasma.enable = true`, setting `stc.relics.pipewire.enable = false` yields `has conflicting definition values` naming `cogitator/nixos/plasma.nix` | It is a defect under criterion 3 (see below), and is fixed in this plan |
| …but the comment the issue quotes | **Gone.** `cogitator/nixos/plasma.nix:26-27` carry no comment today, so the *"already true — override only to disable"* wording the issue cites no longer exists in the file. The cogitator's doc page lists the value as something the profile sets, not as overridable | Criterion 1 does **not** apply to this case; criterion 3 alone carries it. The issue's framing is corrected in the triage |
| Known non-boolean case | `programs.fzf.historyWidget.command` set at normal priority by `cogitator/home/enginseer`, recorded during `v0.16.0` | Scope includes named non-boolean cases, see *Scope* |

### Scope

**In scope:**

- The **141** boolean definitions at normal priority in `relics/` and
  `cogitator/`, including the 26 that target `stc.*` options — the `plasma.nix`
  case proves an internal target hurts a consumer exactly as much as an upstream
  one.
- The non-boolean definitions **already named** as suspects:
  `programs.fzf.historyWidget.command` (enginseer), plus any non-boolean a relic's
  own documentation presents as overridable, found by reading the doc pages of the
  relics touched in step 2 rather than by a second grep.

**Out of scope, with the reason:**

- The remaining ~1000 non-boolean definitions a loose grep returns (lists, paths,
  internal `let` bindings, attrsets of service config). They are not excluded
  because they are safe — they are excluded because there is no tractable
  criterion for them in one chantier, and the three criteria below need a *named
  consumer* to be applied honestly. A follow-up issue is opened at the end if the
  triage shows the boolean pass missing a real class.
- `schematics/`. A schematic is the last word in its own build by design; pinning
  there is not a defect.
- Turning any of this into a lint rule. Tempting, and a separate decision: the
  criteria below are judgement calls, and a rule that fires on all 141 would be
  noise.

### The sorting criteria

Verbatim from the issue — a normal-priority definition is a **defect** when at
least one is true:

1. The relic's documentation (option table, description, or module comment)
   presents the value as overridable.
2. It makes another public STC option unusable — the `plasma6` case.
3. It blocks an identifiable legitimate consumer: a `nixosTest`, a host with
   different hardware, a service that manages the resource itself.

And it is **legitimate** when the value *is* the relic's job: enabling
`stc.relics.pipewire` must set `services.pipewire.enable = true`, and leaving that
at `mkDefault` would weaken the relic for nothing.

A verdict of *legitimate* is written down with the same care as a defect. A line
with no verdict is an unfinished sort, not an implicit pass.

### Global Constraints

- No option is added, renamed or removed; both canonical roots
  (`stc.relics.*`, `stc.cogitator.*`) are untouched.
- Every demoted line keeps the **same effective value** on the default path:
  identity of `drvPath` is the proof, not an argument about `mkDefault` semantics.
- The three schematics must keep evaluating:
  `./schematics/local-vm#…qcow2`, `./schematics/aws-ami#…awsImage`,
  `./schematics/dreadnought#…` (the toplevel it exposes).
- The 11 provings must keep building (`grep -c "nix build .#legacyPackages"
  Justfile` → 11) — `just test` is the only gate that exercises the demoted
  values at runtime.
- Secrets pattern: not touched by this chantier (no `*File` option involved).

### Review Focus

Failure modes no step's verification command exercises, most likely first:

- **A demotion that silently changes behaviour for a consumer who overrides the
  *same* option at normal priority today.** Before: their definition conflicts
  loudly. After: their definition wins silently. That is the intent, but for a
  value they set *by accident* it converts a build error into a behaviour change.
  Identity of `drvPath` cannot see this — it only proves the default path. The
  triage must name, per demotion, who would newly win.
- **`mkDefault` on a value an assertion elsewhere depends on.** The `plasma6`
  case shows the shape: demoting `services.xserver.enable` only helped because the
  SDDM assertion then had a reachable satisfying value. A demotion that makes an
  upstream assertion reachable-but-false moves the error, it does not fix it.
- **A list-valued option demoted by reflex.** `mkDefault` on a list does not
  merge — it replaces or is replaced wholesale. The `relics.hardening.modules`
  ruling of `v0.10.0` is the precedent: adding to a blacklist is possible,
  subtracting is not. Any list in the triage gets that noted rather than demoted.
- **Doc drift in the other direction.** Writing *"overridable since vX"* on an
  option whose demotion is then reverted leaves a false promise in the docs. The
  doc edit belongs in the same commit as the demotion, never earlier.
- **A proving that passes because it asserts the default.** Several provings
  assert values this chantier demotes. Demoting cannot break such an assert (the
  default path is identical), which means `just test` green is **not** evidence
  that the override now works. Step 3 exists for that reason.

### Affected Files

Known before the sort; step 2 extends this list from its own findings.

- [ ] `.claude/plans/v0.18.0/triage.md` — the sort, the main deliverable
- [ ] `.claude/plans/v0.18.0/progress.md` — the ledger
- [ ] `cogitator/nixos/plasma.nix` — third known case, measured
- [ ] `cogitator/home/enginseer/default.nix` — 36 candidates, the largest single file
- [ ] `relics/nixos/*.nix` / `cogitator/nixos/*.nix` — per the sort
- [ ] `docs/src/content/docs/{en,fr}/relics/*.md` — per demotion: how to override, and since which version
- [ ] `docs/src/content/docs/{en,fr}/reference/` — the rule itself, once

### Atomic Steps

#### Step 1: Sort the 141 candidates

**Description:** Produce `triage.md`: one row per candidate — file, line, option
path, value, verdict (*defect* / *legitimate*), the criterion that decides it,
and for a defect, **who** it blocks. No code changes in this step. The row for a
candidate whose verdict needs a measurement carries the command and its output.

Rows are grouped by file, files ordered by candidate count, so the largest
offender (`cogitator/home/enginseer/default.nix`, 36) is faced first rather than
last.

**Files changed:**
- `.claude/plans/v0.18.0/triage.md`

**Interfaces:**
- Consumes: the inventory command below.
- Produces: the defect list step 2 consumes, as `file:line → option path`.

**Verification command(s):**

```bash
# The inventory this step must cover in full — 141 rows expected.
grep -rnE "^\s*[a-zA-Z_\"][a-zA-Z0-9_.\"@-]*\s*=\s*(true|false)\s*;" relics/ cogitator/ --include="*.nix" \
  | grep -v "mkDefault\|mkForce\|mkOverride" \
  | grep -vE "^[^:]+:[0-9]+:\s*(default|defaultText|example|internal|visible|readOnly)\s*=" \
  | wc -l

# Every inventory row appears in the triage, and every triage row has a verdict.
grep -c "^| \`" .claude/plans/v0.18.0/triage.md
grep -c "defect\|legitimate" .claude/plans/v0.18.0/triage.md
```

**Commit message:** `docs(plans): sort every normal-priority definition in relics and cogitators`

---

#### Step 2: Demote the defects, one commit per file

**Description:** For each file holding at least one defect, demote its defect
lines to `lib.mkDefault`, add the module comment saying **why** (so nobody
"simplifies" it back to a bare value), and record the `drvPath` identity. One
commit per file keeps each demotion independently revertable — which matters,
because a demotion is the kind of change whose regression shows up at a
consumer's next bump, not here.

A file whose every candidate is *legitimate* produces no commit. That is a
result, not a gap.

**Files changed:**
- Per the sort; `cogitator/nixos/plasma.nix` is known to be one of them.

**Interfaces:**
- Consumes: the defect list from step 1.
- Produces: for step 4, the list of `(option path, version)` pairs the docs must
  describe as overridable.

**Verification command(s):**

```bash
# Innocuousness — same drvPath before and after, per schematic.
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file

# Usefulness — the override that was impossible must now evaluate and produce
# the expected value. Per demotion, written as a probe under the scratchpad:
#   nix-instantiate --eval --json ./probe.nix --arg override true
```

**Commit message:** `fix(relics): make <option> overridable` / `fix(cogitator): …` — one per file

---

#### Step 3: Prove one demotion at runtime

**Description:** Identity of `drvPath` proves nobody is hurt; it proves nothing
about the override working. Pick the demotion with the most consequential
override path among those found — `cogitator/nixos/plasma.nix` if it survives the
sort, since a Plasma host without Pipewire is the case a consumer actually asks
for — and set that override on a proving node, so one override is exercised in a
booted VM rather than only at evaluation.

If the sort finds no defect whose override is reachable from an existing proving,
this step is dropped with the reason in the ledger instead of inventing a node
for it.

**Files changed:**
- `provings/<name>.nix`

**Verification command(s):**

```bash
just test   # 11 provings
```

**Commit message:** `test(provings): exercise the <option> override`

---

#### Step 4: Document the rule and the per-option escape hatch

**Description:** Two different pieces of writing, both needed:

1. Per demoted option, on the relic's own page (EN + FR): how to override it, and
   **from which version** — a consumer who worked around the pin with `mkForce`
   must learn they can drop it.
2. The rule itself, once, in `docs/{en,fr}/reference/`: when a relic pins and when
   it proposes, i.e. the three criteria, so the next relic is written right rather
   than audited later.

**Files changed:**
- `docs/src/content/docs/{en,fr}/relics/*.md`
- `docs/src/content/docs/{en,fr}/reference/…`

**Verification command(s):**

```bash
just ci                                   # includes docs-parity
cd docs && nix develop ..#docs --command npm run build
```

**Commit message:** `docs(relics): record which pinned options became overridable`

---

### Quality Gates

- [ ] `just ci` green (fmt-check + lint + flake check + docs parity)
- [ ] `just test` green — 11 provings
- [ ] `drvPath` identity recorded for all three schematics, per demotion commit
- [ ] At least one override proved useful (evaluation), and one at runtime (step 3)
- [ ] Docs EN + FR updated in the same commit as the demotion they describe
- [ ] Every one of the 141 inventory rows carries a written verdict
- [ ] Closing review by one fresh context

### Open questions for the user

Three, and they change the shape of the work:

1. **Scope of the non-booleans.** The plan keeps the 141 booleans plus the
   already-named non-boolean cases, and declines the ~1000-row loose grep with the
   reason written down. The alternative — sorting everything — is a different
   chantier, not a bigger one.
2. **Where the triage lives.** Proposed: `triage.md` beside this plan, committed,
   and only the *rule* in the public docs. The alternative is a reference page
   listing all 141 verdicts, which ages badly as files move.
3. **How far a "legitimate" verdict goes.** The plan treats "the value is the
   relic's job" as legitimate even when a consumer might want otherwise (e.g.
   `services.pulseaudio.enable = false` in the Pipewire relic). Demoting those
   too is defensible and would grow step 2 substantially.
