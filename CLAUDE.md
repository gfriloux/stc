# CLAUDE.md — STC project instructions

## Architecture

Read DESIGN.md first. It defines what belongs where and why. All decisions flow from it.

## Namespace rules

Options live under two canonical roots:
- Relics: `stc.relics.<domain>.*`
- Cogitators: `stc.cogitator.<profile>.*`

**Internal code (cogitators, schematics) must always use canonical namespaces.**
Never use deprecated aliases inside the repo — they exist only for external consumers.

## Namespace migrations — checklist

When renaming or moving any option namespace, ALL of the following must happen in the same change:

1. Add `lib.mkRenamedOptionModule` for every renamed leaf option (both relic and cogitator options).
2. Update every internal reference in `cogitator/` to the new canonical namespace.
3. Update every internal reference in `schematics/` to the new canonical namespace.
4. Verify: `nix flake check` passes.
5. Verify: `nix eval <schematic>#nixosConfigurations.<name>.config.system.build.<artefact>.drvPath` succeeds for each schematic.

Missing step 2 or 3 causes a hard eval error with no helpful message — the deprecated alias only exists for external consumers, not internal code.

## Verification commands

```bash
# Full check
nix flake check --no-write-lock-file

# Evaluate each schematic
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file

# Find stale internal references after a rename
grep -rn "stc\." relics/ cogitator/ schematics/ --include="*.nix" \
  | grep -v "options\.stc\." \
  | grep -v "cfg = config\.stc\." \
  | grep -v "stc\.relics\." \
  | grep -v "stc\.cogitator\." \
  | grep -v "stc\.lib\." \
  | grep -v "^.*#"
```

## Dev shell

```bash
nix develop          # Nix tools (alejandra, statix, deadnix, just)
nix develop .#docs   # Node.js for Astro/Starlight docs
just ci              # format + lint + flake check
```

## Secrets pattern

Options that accept secrets use a `*File` suffix — never inline values.
The module reads the file at runtime. STC is agnostic to the secrets backend.

## Adding a new relic

1. Create `relics/nixos/<name>.nix` or `relics/home/<name>.nix`.
2. Declare options under `stc.relics.<name>` (or `stc.relics.<group>.<name>`).
3. Register in `relics/default.nix` under `flake.nixosModules` or `flake.homeModules`.
4. Add a bilingual doc page in `docs/src/content/docs/en/` and `fr/`.

## Adding a new cogitator

1. Create `cogitator/nixos/<name>.nix` or `cogitator/home/<name>.nix`.
2. Declare options under `stc.cogitator.<name>`.
3. In the `config` block, reference relics via `stc.relics.*` (canonical namespace).
4. Register in `cogitator/default.nix`.
5. Add a bilingual doc page.

## Structural changes — mandatory doc sync

Any structural change (new relic, renamed option, new cogitator, new schematic) requires a documentation update **in the same change**. Never split structural changes from their doc updates.

Doc update checklist:
1. Check for stale option references in docs:
   ```bash
   grep -rn "stc\." docs/src/content/docs --include="*.md" --include="*.mdx" \
     | grep -v "stc\.relics\." | grep -v "stc\.cogitator\." | grep -v "stc\.lib\." \
     | grep -v "stc\.nixosModules\." | grep -v "stc\.homeModules\."
   ```
2. Update every option example in `docs/src/content/docs/en/` and `fr/` that references a renamed option.
3. If a relic is added/renamed: update `docs/en/relics/index.md` and `docs/fr/relics/index.md`.
4. If a cogitator is added/renamed: update `docs/en/cogitator/index.md` and `docs/fr/cogitator/index.md`.
5. If a schematic changes: update the corresponding schematic doc page (EN + FR).
6. New pages must exist in both languages before the change is complete.
