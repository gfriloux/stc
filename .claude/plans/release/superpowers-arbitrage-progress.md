# Ledger — plan: .claude/plans/release/superpowers-arbitrage.md

Pre-flight: step 4's table references anchors created in steps 1 and 2
(`#sizing-a-change`, `#debugging--root-cause-before-fixes`,
`#verification--evidence-before-claims`, `#tests--what-replaces-tdd`,
`#closing-review--one-fresh-context`) — consumed names match the headings
produced. Step 3 consumes nothing from 1–2. Checked, clean.

Step 1: complete (c485656, headings and ToC anchors resolve)
Step 2: complete (811033d, ledger path matches `.claude/plans/README.md`)
Step 3: complete (80295ed, this plan satisfies the extended template)
Step 4: complete (1aa382d, 15/15 skills in the PROCEDURE_PLANS.md table)

Step 4: Ruling: the historical plans under `.claude/plans/` that state the user
merges/tags/pushes are left untouched — they are records of chantiers completed
under the norm in force at the time, and editing them would falsify the record.
The authority on the current norm is `CLAUDE.md` / `PROCEDURE_PLANS.md`, changed
in `1fbcb59`. Cost if wrong: a future reader takes a dated plan for the current
rule; mitigated by both normative documents saying otherwise.

Step 4: Ruling: the arbitration verdicts are written twice — the full table with
rationale in `PROCEDURE_PLANS.md`, a condensed one in `CLAUDE.md` — per the
user's choice of location. Accepted cost: the two can drift. `CLAUDE.md` points
at `PROCEDURE_PLANS.md` as the authority, so a divergence resolves in favour of
the latter.

## Final review

Fresh-context review dispatched over `main..HEAD` with the plan, its Review Focus
verbatim, and this ledger. Returned 3 Critical, 11 Important, 6 Minor. Re-graded
by effect: the three Criticals stand; three Minors were re-graded up to Important
(a copy-paste-broken `git merge-base` range, the Bounded/Documentation-Only
contradiction over whether a typo needs approval, and `subagent-driven-development`
recorded as flat "Rejected" against the user's actual decision of "rejected by
default"). Two findings were the author's own factual errors and are corrected
rather than defended.

Fixed in one pass (`2b9a492`):

- **Critical** — Both cogitator recipes (`PROCEDURE_PLANS.md` Step 1–4,
  `CLAUDE.md` 1–5) presented themselves as complete and omitted the proving the
  new test law requires. A reader could ship a cogitator, pass every gate the
  procedure named, and never write one. Added as Step 5 / item 6, naming all
  three files that change together.
- **Critical** — `CLAUDE.md`'s "Every change is planned before code" defeated
  *Sizing a Change* from the one file injected into every session. Rewritten to
  classify first; only architectural changes get a plan file.
- **Critical** — §Quality Gates (the normative list) still had five gates and
  never mentioned provings or doc parity, while the template's embedded checklist
  had gained both. Two gate lists disagreed. §Quality Gates now has seven,
  including behaviour and the fresh-context review.
- **Important** — `just test` built only `hardening` and `docker-server` while
  `provings/default.nix` registers `workstation` too. A change to
  `cogitator/nixos/workstation.nix` would have gone green with its only proving
  never built — the exact false green §Verification exists to prevent. Added to
  the recipe with a comment tying it to the registry.
- **Important** — The ledger fixed one ledger per release; multi-chantier
  releases already exist (`v0.4.0`, `v0.6.0`). Now one ledger per plan *file*,
  with the naming table.
- **Important** — "Rule, don't stall" was unexecutable for bounded changes, which
  have no plan and therefore no ledger. Stated: their rulings go into the closing
  message, which is then the only record.
- **Important** — `CLAUDE.md`'s table covered 13 of 15 skills with no Marginal
  row, a failure mode this plan's own Review Focus named. Now 15, and the gate
  line below is about both files.
- **Important** — The seven verdict words carried the table undefined. Added a
  legend stating what each obliges.
- **Important** — Author's error: the `using-git-worktrees` rationale claimed a
  worktree "refetches every flake input". False — inputs resolve from
  `flake.lock` into the shared store; what is lost is `.direnv` and the eval
  cache. It also claimed the skill's setup step assumes `npm install`/`cargo
  build`, whereas that step is guarded and a no-op here. Both corrected, and the
  verdict narrowed to the skill's manual workflow rather than any worktree.
- **Important** — Author's error: `just docs-parity` was offered as proof that
  "the docs are consistent". It compares the *set of file paths* and nothing
  else. Claim narrowed to what the script actually checks, with the gap named.
- **Important** — `requesting-code-review` was labelled Adopted while being
  materially narrowed from per-task to one review at branch close. That is
  Adapted in this table's own vocabulary. Re-labelled.
- **Important** — The closing review required "a context that did not write it"
  without saying how to obtain one. Now: dispatched subagent first, a `/clear`ed
  session otherwise, and the user's go-ahead is explicitly not a substitute.
- **Important** — The closed list of "four things stop the work" omitted the
  three-failed-fixes architectural stop introduced 110 lines earlier — the stop
  that matters most was the one excluded. Now five.
- **Important** (re-graded up from Minor) — `` `git merge-base main HEAD`..`HEAD` ``
  is not a usable range; anyone copying it gets an error. Fixed to
  `$(git merge-base main HEAD)..HEAD`.
- **Important** (re-graded up) — Bounded included "a doc correction" and demanded
  an explicit yes, while §Documentation-Only Updates lists "fix typo" with no
  gate. Added a **Trivial** row: no artefact, no approval.
- **Important** (re-graded up) — `subagent-driven-development` was recorded as
  flat "Rejected" in both tables; the decision was *rejected by default*. A
  reader would have refused a direct request citing the table. Now "Rejected by
  default", with the opt-in and the ~8-step threshold for proposing it.
- Also corrected in the same pass: "Four rules govern how a step is worked" headed
  a five-subsection section, two of which are per-branch rather than per-step.

Ruling: Correction to this ledger's own gate line. It previously recorded "no
surviving normative claim that Claude does not merge/push/tag" as passed, from a
grep that matched English only. The review found seven files, not three — the
plans for `v0.5.0`, `v0.6.0` (×2) and `v0.7.0` say *« l'utilisateur merge/push »*.
The ruling above is unchanged and covers all seven; what failed was the
verification, in the very change that makes "no claim without the command run in
this message" law. The proof table now says a grep must match the language the
file is in.

Final: minor (deferred): the triage is called **probe**/bounded/architectural here
while the plugin's `brainstorming` calls it **spike**; anyone grepping the plugin
for "probe" finds nothing. Naming choice, left to the user.

Final: minor (deferred): `writing-skills` is Adopted "for STC's own skills", which
live in `~/.claude/skills/` — outside this repo, so no gate here can check it. It
reads as a note rather than an enforceable rule.

Gates: docs-parity OK · anchors resolve in both files · 15/15 skills in both
tables · `provings/default.nix` and the `test` recipe now list the same three
provings · `just --list` parses · `nix eval …provings.workstation.drvPath`
succeeds. **`just test` itself was not run** — three VM boots, and this branch
changes no cogitator, so Gate 5 does not fire; the new recipe entry is verified
by evaluation only.
