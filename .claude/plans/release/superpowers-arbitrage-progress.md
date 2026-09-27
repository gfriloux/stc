# Ledger — plan: .claude/plans/release/superpowers-arbitrage.md

Pre-flight: step 4's table references anchors created in steps 1 and 2
(`#sizing-a-change`, `#debugging--root-cause-before-fixes`,
`#verification--evidence-before-claims`, `#tests--what-replaces-tdd`,
`#closing-review--one-fresh-context`) — consumed names match the headings
produced. Step 3 consumes nothing from 1–2. Checked, clean.

Step 1: complete (c485656, headings and ToC anchors resolve)
Step 2: complete (811033d, ledger path matches `.claude/plans/README.md`)
Step 3: complete (80295ed, this plan satisfies the extended template)

Step 4: Ruling: three historical plans under `.claude/plans/release/`
(`plan.md`, `docs-astro7.md`, `docs-build-on-pr.md`) still state that the user
merges/tags/pushes. Left untouched — they are records of chantiers completed
under the norm in force at the time, and editing them would falsify the record.
The authority on the current norm is `CLAUDE.md` / `PROCEDURE_PLANS.md`, changed
in `1fbcb59`. Cost if wrong: a future reader takes a dated plan for the current
rule; mitigated by both normative documents saying otherwise.

Step 4: Ruling: the arbitration verdicts are written twice — the full table with
rationale in `PROCEDURE_PLANS.md`, a condensed one in `CLAUDE.md` — per the
user's choice of location. Accepted cost: the two can drift. `CLAUDE.md` points
at `PROCEDURE_PLANS.md` as the authority, so a divergence resolves in favour of
the latter.

Verification note: the first anchor check reported six broken anchors. The
checker was wrong, not the document — it collapsed runs of whitespace into one
hyphen, whereas GitHub maps each space to its own hyphen, which is what a title
containing an em dash or an `&` produces. Re-run with the correct rule: zero
broken anchors, including the pre-existing `#plans--releases`.

Gates: docs-parity OK · 21 anchors resolve · 15/15 skills arbitrated · no `.nix`
in the diff · no surviving normative claim that Claude does not merge/push/tag.
