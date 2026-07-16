# Plans — STC

This directory holds every planning document, following the convention shared with
the sibling projects `astropath` and `auspex`.

## Layout

- `vX.Y.Z/` — the plan that produced release `vX.Y.Z`. Each directory holds at
  least `plan.md` (context, scope, atomic steps, decisions). A release built from
  more than one chantier keeps one file per chantier.
- `release/` — plans about tooling and project infrastructure (tagging, changelog,
  CI, working methods) rather than a single product feature.

Rules:

- Plans always live here, **never at the repository root**.
- An obsolete plan is **deleted**, never duplicated as `_v2` / `_v3`.
- A plan is authored before any code (see [`PROCEDURE_PLANS.md`](../../PROCEDURE_PLANS.md)).

## Retroactive version map

STC shipped its first six releases before tags existed. The tags below were
created retroactively from the git history, one per completed body of work:

| Tag | Commit | Date | Content | Plan |
|-----|--------|------|---------|------|
| `v0.1.0` | `6c5dfab` | 2026-06-02 | Genesis: relics/cogitators/schematics, plasma-manager, packages | — |
| `v0.2.0` | `2431ff3` | 2026-06-06 | `stc.relics.*` namespace + remediation P0–P3 (introduces the deprecated aliases) | [`v0.2.0/`](v0.2.0/plan.md) |
| `v0.2.1` | `541a520` | 2026-06-07 | Remediation round 2 | [`v0.2.1/`](v0.2.1/plan.md) |
| `v0.2.2` | `d255765` | 2026-06-08 | Remediation round 3 | [`v0.2.2/`](v0.2.2/plan.md) |
| `v0.3.0` | `04496d3` | 2026-07-03 | Purity Seals (internalized CI checks) | [`v0.3.0/`](v0.3.0/plan.md) |
| `v0.4.0` | `0adfb94` | 2026-07-04 | The Provings (nixosTest) + ANSSI-BP-028 matrix | [`v0.4.0/`](v0.4.0/plan.md) |
| `v0.5.0` | `f23853d` | 2026-07-12 | Docker relics refactor (architectural debt) | [`v0.5.0/`](v0.5.0/plan.md) |
| `v0.6.0` | `8e60932` | 2026-07-16 | Hardening absorption (3-B) + workstation cogitator (3-C) | [`v0.6.0/`](v0.6.0/plan.md) |

The deprecated `stc.*` aliases (introduced in `v0.2.0`) are scheduled for removal
in the next **major** release, `v1.0.0` — no calendar date.
