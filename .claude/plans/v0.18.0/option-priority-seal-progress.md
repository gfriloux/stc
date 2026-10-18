# Ledger — plan: .claude/plans/v0.18.0/option-priority-seal.md

Pre-flight: every verification command in the plan was measured before being
written into it, including the one that decided the design (bare-leaf sweep →
7 false positives, rejected) and the cost of resolving the locked input paths
(4.5 s).

Step 1: Ruling: the register carries the full option path **by hand**, and the
machine enforces completeness through per-file counts rather than inferring paths
from source. Inference was the first design and it does not work: a nested block
yields a bare leaf that names nothing greppable (`enable`, `mouse`, `silent`), and
`{historyWidget.command` leaked a brace into the attribute name. Cost if wrong:
a path typed incorrectly in the register silently waters down one row's sweep —
mitigated because the counts still force a row to exist and carry a reason.

Step 1: Ruling: comments are stripped before counting. The raw grep gave 132
occurrences, of which 55 were modules discussing `mkForce` in prose — including
comments this very chantier wrote. Counting those would make the register a
transcription of the documentation. Code-only count: **77**, across 21 files.

Step 1: **The first draft of the sweep was a false green, and measuring caught
it.** The pattern `[^.a-zA-Z]<leaf>[[:space:]]*=` excluded a preceding dot, so it
reported 0 competing `mkDefault` for `X11Forwarding` — the exact collision the
seal exists to detect, which I had already measured by hand an hour earlier.
Upstream writes the full dotted path, so the guard excluded every real case.
Fixed to `[.[:space:]]`, then re-measured: slurm found.

Step 1: Ruling: the sweep matches the full dotted path **and** the last two
components, never a bare leaf. Bare leaves produced 7 hits on the first run, all
false (`command` matching `default_session.command`, `package` matching every
`*.package`, `enable` matching everything). A check that cries wolf gets
disabled, so precision wins over the residual blind spot — a module writing only
a bare leaf inside a nested block can still slip past, and the docs say so.

Step 3: **The seal found a real defect on its first green-path run, older than
issue #86.** `relics/nixos/networking.nix` wrote `networking.useDHCP =
lib.mkDefault true`; `networking.ifstate` writes the same option `mkDefault
false`. Measured on both refs: the networking relic plus
`networking.ifstate.enable = true` **fails to evaluate on `main`** with
`has conflicting definition values`, and evaluates on this branch. Fixed with
tier 1 of the rule — `stc.relics.networking.dhcp`, an option at normal priority.

Step 3: I nearly discarded that finding through my own bad measurement. The
second probe used `services.ifstate.enable`, which does not exist (the option is
`networking.ifstate`), so it failed with "option does not exist" and I read it as
"the fix did not work". Reading the error text rather than the pass/fail is what
recovered the true result. Same error profile as the rest of this session: a
failure attributed to a cause without reading the message.

Step 3: Precise claim about what the `dhcp` option changes, since "fixes the
collision" would overstate it. On `main`: `has conflicting definition values`,
opaque, no clean way out. On this branch: either the host builds — with
`dhcp = false` — or it fails on **ifstate's own assertion**, which names the
problem and links the upstream issue. The failure is converted from a Nix
priority puzzle into an actionable message, not removed.

Step 2/4: the seal was seen **red on both classes it guards** before being
trusted: an unregistered `lib.mkDefault` added to `relics/nixos/boot.nix` (caught,
counts 1 vs 2) and the slurm collision deliberately re-introduced in
`relics/nixos/hardening/ssh.nix` (caught, quoting `slurm.nix:491` verbatim). Both
reverted afterwards, `git diff` confirmed empty.

Final: `just ci` green with the new gate, 21 files registered and 27 third-party
options watched; `drvPath` of the three schematics still byte-identical to the
pre-audit baseline.

Final: minor (deferred): the seal does not look at normal-priority definitions at
all — it has nothing to say about the 93 the triage ruled legitimate, and it
cannot tell a *missing* priority (a bare value that should be a default) from a
deliberate one. That is the triage's job, and the triage is a snapshot. Closing
that gap would need evaluation-level work that `highestPrio` cannot do in bulk
(see the v0.18.0 ledger).
