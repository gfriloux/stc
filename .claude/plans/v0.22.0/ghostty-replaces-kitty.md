## Feature Plan: ghostty replaces kitty (#1)

**Type:** Architectural — a public module (`relics-kitty`) is withdrawn, and a
responsibility (the Nerd Fonts) moves from one relic to another.

**Goal:** `cogitator.desktop` ships ghostty as its only terminal; the kitty
relic is removed, and any consumer still setting its options gets an
evaluation warning instead of an error.

**Why:** ghostty tested and adopted on every workstation (#1). Two terminals
in one profile meant a consumer wanting one had to switch the other off.

### User decisions (2026-10-30)

- Remove kitty now, not at v1.0.0: pre-1.0, breaking is allowed.
- Not brutally: external code still using it gets a warning, not an error.
- The Nerd Fonts move onto the ghostty relic.
- Lot v0.22.0 = #1, #40, #31, #33.

### Measured premises (2026-10-30)

- The known consumer `gfriloux/nixos` imports `cogitator-desktop` and sets
  `programs.ghostty`, never a kitty option: it loses kitty silently and keeps
  its fonts through `ghostty.fonts.enable`.
- `stc.relics.gui.kitty.fonts.enable` is the only carrier of the seven font
  packages today; dropping kitty without moving it would silently remove them.

### Design

- `relics/home/kitty.nix` becomes a stub: no `config` besides `warnings`.
  Both options stay declared (`enable`, `fonts.enable`) as `nullOr bool`,
  default `null`, `visible = false`; any non-null definition warns. `null`
  rather than `bool` so that `kitty.enable = false`, the documented way to
  keep only ghostty, also warns: that line is dead code now.
- The `stc.gui.kitty.*` aliases stay: they forward to the stub, which warns.
- `relics-kitty` stays in `homeModules` and in the cogitator's imports, so an
  import or a definition never turns into "option does not exist".
- `relics/home/ghostty.nix` gains `fonts.enable` (default `true`) with the
  seven packages.
- `cogitator/home/desktop.nix` drops `kitty.enable`.

### Global Constraints

- No consumer build breaks; a consumer setting a kitty option sees a warning.
- The stub disappears with the `stc.*` aliases at v1.0.0.

### Review Focus

- Every way a consumer can still reach kitty: module import, canonical
  option, deprecated alias, both `enable` and `fonts.enable`.

### Affected Files

- `relics/home/kitty.nix`, `relics/home/ghostty.nix`,
  `cogitator/home/desktop.nix`, `cogitator/default.nix` (comment)
- `provings/home-desktop.nix`
- `docs/src/content/docs/{en,fr}/`: `relics/home-apps.md`, `relics/index.md`,
  `cogitator/desktop.md`, `cogitator/index.md`,
  `reference/overridable-defaults.md`, `getting-started.md`,
  `architecture.md`, `provings/index.md`

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: fonts onto ghostty, kitty stub, cogitator without kitty
#### Step 3: proving — fonts through ghostty, no kitty by default
#### Step 4: docs EN + FR

### Quality Gates

- `just ci`, `just test` green (at least `home-desktop` built).
- Warning measured by eval: canonical option, alias, `fonts.enable`; none
  without a definition.
- Consumer `gfriloux/nixos` evaluates with `--override-input`.
- One fresh-context review at branch close.
