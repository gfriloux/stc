## Maintenance Plan: a purity seal for option priorities

**Type:** Tooling — a new internalized CI check (`just ci`)

**Goal:** Make the priority rule something a command enforces, instead of
something I remember.

**Why:** Issue #86 produced a rule, wrote it into `DESIGN.md`-adjacent docs, and
then **still shipped a regression of exactly the class the rule describes**:
demoting `services.openssh.settings.X11Forwarding` to `lib.mkDefault` collided
with nixpkgs' slurm module, which writes the same setting as
`mkIf cfg.client.enable (mkDefault true)`. A hardened Slurm client that built on
the previous release stopped evaluating. The closing review caught it; nothing in
the repository would have.

That is the argument for this chantier. A rule without a gate failed once here
already, and the failure mode is silent — it appears at a consumer's next bump,
not in our CI.

**Architecture:** A bash seal in the house style of
`scripts/check-docs-parity.sh`, plus a register, wired into `just ci`. It sits
beside the pillar `DESIGN.md` calls Purity Seals, and owns no Nix evaluation of
its own beyond resolving the locked input paths.

### Global Constraints

- No option namespace changes; the seal reads source and the locked inputs only.
- `just ci` must stay usable offline-ish: the only Nix call is resolving
  `inputs.nixpkgs` / `inputs.home-manager` out-paths (measured: ~4.5 s).
- The three schematics must keep evaluating identically.

### What it checks

1. **Completeness.** Every file under `relics/` and `cogitator/` writing
   `lib.mkDefault` / `lib.mkForce` / `lib.mkOverride` has a register row with the
   exact count and a reason. Adding one without registering fails CI.
2. **No silent collision.** For every third-party option the register says STC
   writes with `mkDefault`, the locked nixpkgs and home-manager are searched for
   a module writing the same option with `mkDefault`. Hits must be allow-listed
   with a measured reason.

### Measured before writing it

| Question | Answer |
|---|---|
| Can option paths be inferred from source? | **No.** A nested block yields a bare leaf (`enable`, `mouse`) that names nothing greppable, and a `{` leaks into the attribute name. The register carries the path by hand; the counts stop it drifting. |
| Can the sweep match bare leaves? | **No** — `command`, `package`, `enable` hit half of nixpkgs. Full dotted path plus last-two-components: 1 real hit, 0 noise on the current tree. |
| Must the pattern allow a leading dot? | **Yes**, and this is how the first draft missed slurm: upstream writes the full dotted path, so a `[^.]` guard excluded exactly the case the seal exists for. |
| Cost of resolving input paths | `nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath'` → 4.5 s |
| Does comment text pollute the counts? | **Yes** — several modules discuss `mkForce` in prose, so comments are stripped before counting. |

### Review Focus

- A seal that cries wolf gets disabled. Hence the allowlist, and hence rejecting
  the bare-leaf sweep that produced 7 false positives on the first run.
- A seal nobody has seen fail proves nothing — both failure paths are exercised
  deliberately (see the ledger).
- The counts check is coarse by design: it detects *that* a priority appeared,
  not whether it is right. The reason column is where the judgement lives, and
  no machine can check that.

### Atomic Steps

1. `scripts/check-option-priorities.sh` + `scripts/option-priorities.tsv`.
2. Wire `just option-priorities`, append to `ci`.
3. Fix whatever the first run finds (it found one, pre-existing).
4. Document the seal and its blind spot in `reference/overridable-defaults.md`
   (EN + FR).

### Quality Gates

- [ ] `just ci` green, now including `option-priorities`
- [ ] the seal seen **red** on both classes it guards, then green
- [ ] `just test` green
- [ ] `drvPath` identity on the three schematics
- [ ] docs EN + FR, parity green
