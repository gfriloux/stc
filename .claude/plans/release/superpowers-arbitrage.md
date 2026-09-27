# Superpowers Arbitration — Plan

**Type:** Working methods (tooling/process, not a product feature)

**Goal:** Decide, once and in writing, which parts of the `superpowers` plugin
govern work on STC and which are overridden — so the plugin's `SessionStart`
hook cannot re-open the question every session.

**Why:** `superpowers` 6.4.1 injects the full text of its `using-superpowers`
skill into every session (hook matcher `startup|clear|compact`), wrapped in
`<EXTREMELY_IMPORTANT>`, with the rule "if there is even a 1% chance a skill
applies, you MUST invoke it". Several of its skills contradict STC's norms
outright — its TDD Iron Law cannot be satisfied by Nix modules whose tests boot
a VM, and its plan/spec locations collide with the bilingual Astro tree under
`docs/`. The plugin itself resolves this in our favour: "User instructions
(CLAUDE.md, AGENTS.md, etc.) take precedence over skills." That only works if
the arbitration is actually written down.

**Architecture:** The detailed rules live in `PROCEDURE_PLANS.md`, which is
already the single process entry point. `CLAUDE.md` carries a short arbitration
table so the verdict is in context from the first token of every session,
including after a compaction.

**Spec:** none — this plan is its own spec. The source material is
`~/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/`.

## Global Constraints

- No `.nix` file is touched. `nix flake check`, `fmt-check` and `lint` are not
  in scope; `just docs-parity` is (it guards `docs/`, which stays untouched).
- Nothing lands under `docs/` — the arbitration is process documentation, not
  user-facing documentation, so the EN/FR parity requirement does not apply.
- Plans and ledgers stay under `.claude/plans/`, never in `docs/superpowers/`.
- The four decisions taken with the user on 2026-09-27 are settled inputs, not
  open questions:
  1. Tests: Nix gates are the law; every **new cogitator** ships a proving.
  2. Ledger: `.claude/plans/vX.Y.Z/progress.md`, committed.
  3. `subagent-driven-development`: rejected by default.
  4. Location: `PROCEDURE_PLANS.md` for the rules, `CLAUDE.md` for the table.

## Review Focus

Failure modes this change must not introduce, checked deliberately at the end:

- A rule that reads as advice rather than a gate — an arbitration that does not
  say "this one wins" loses to the hook's `<EXTREMELY_IMPORTANT>` framing.
- A skill left unarbitrated: all 15 must appear in the table, including the ones
  whose verdict is "marginal here".
- A stale claim that Claude never merges/pushes/tags — that norm changed in
  `1fbcb59` and `finishing-a-development-branch` is now adopted, not rejected.
- An anchor in the Table of Contents that points at a heading that does not
  exist (the previous change already needed one such fix).
- A proving requirement written so loosely that it silently applies to relics,
  which the user explicitly scoped out.

---

## Atomic Steps

### Step 1: Sizing a change

**Description:** Import `brainstorming`'s spike/bounded/architectural triage,
mapped onto STC's change types, with the one-way ratchet. Replaces the implicit
"every change gets a plan file" reading of Phase 1.

**Files changed:** `PROCEDURE_PLANS.md` (new section + ToC entry)

**Verification:** headings match the ToC anchors; `grep -n "^## "` reads in order.

**Commit message:** `docs(procedure): size a change before planning it`

---

### Step 2: Execution discipline

**Description:** Four rules adopted from superpowers, adapted to Nix:
root-cause-first debugging with the 3-failed-fixes architectural stop; the
verification gate function; the test law that replaces the TDD Iron Law; the
fresh-context review before closing a branch. Plus the ledger format.

**Files changed:** `PROCEDURE_PLANS.md` (new section + ToC entry),
`.claude/plans/README.md` (ledger in the layout)

**Verification:** the test law names cogitators and not relics; the ledger path
matches `.claude/plans/README.md`.

**Commit message:** `docs(procedure): add execution discipline (debug, verify, test, review, ledger)`

---

### Step 3: Plan template

**Description:** Extend the template with `writing-plans`' useful parts — Goal /
Architecture / Global Constraints / Review Focus header, per-step
Consumes/Produces interfaces, and the no-placeholders rule. The interfaces block
is the guard the namespace-migration checklist lacks: it makes "step 2 updates
`cogitator/`, step 3 updates `schematics/`" a declared dependency instead of a
thing to remember.

**Files changed:** `PROCEDURE_PLANS.md`

**Verification:** this very plan file satisfies the new template.

**Commit message:** `docs(procedure): extend the plan template with constraints and interfaces`

---

### Step 4: Skill arbitration table

**Description:** One row per superpowers skill with its verdict, in
`PROCEDURE_PLANS.md`, and the condensed table in `CLAUDE.md`.

**Files changed:** `PROCEDURE_PLANS.md`, `CLAUDE.md`

**Verification:** 15 rows, one per skill under `superpowers/6.4.1/skills/`.

**Commit message:** `docs(procedure): arbitrate the superpowers skills`

---

## Quality Gates

- [ ] `bash scripts/check-docs-parity.sh` passes (nothing under `docs/` moved)
- [ ] Every ToC anchor resolves to an existing heading
- [ ] All 15 superpowers skills appear in the arbitration table
- [ ] No surviving claim that Claude does not merge/push/tag
- [ ] No `.nix` file in the diff
- [ ] Commits atomic, Conventional Commits, one logical change each
