# Ledger — plan: .claude/plans/v0.25.0/options-reference.md

Pre-flight: steps 2–4 consume `docs/src/options/{en,fr}/<slug>.md` produced by
step 1, with `<slug>` = declaring path, `/` → `-`, `.nix` dropped; step 5
consumes the import lines written in 2–4 (`options/en/<slug>.md'`). Checked:
the generator's `slug` and the coverage map's names match (`relics-nixos-heartbeat`,
`cogitator-home-enginseer`, `relics-home-yubikey`).

Step 1: Ruling: 47 fragments, not 48 — the plan's count added
`relics/home/yubikey.nix` to a list of 47 that still contained nixpkgs'
`lib/modules.nix` (the `._module.*` internals, filtered out). 46 + 1 = 47;
180 options (173 NixOS, 7 HM) as planned — cost if wrong: none, the coverage
check of step 5 counts the files themselves.
Step 1: Ruling: values are `lib.trim`med before rendering — multi-line examples
ended with a newline that produced a whitespace-only line in the fenced block —
cost if wrong: a default whose meaning depends on surrounding whitespace, none
exists.
Step 1: Ruling: the recipe copies with `cp -rL` — `linkFarm` output is
symlinks into the store; a plain copy would commit symlinks — cost if wrong:
none.
Step 1: Ruling: `just options-doc` ends with `git add docs/src/options` — a
flake reads tracked files only, so freshly generated fragments were invisible
to the check (measured: "docs/src/options: No such file or directory") — cost
if wrong: the recipe touches the index, which a reader may not expect; the
comment above the line says why.
Step 1: complete (checks.options-doc → OK on the clean tree; a planted description change → fails with "out of date"; nix flake check → exit 0).
