## Maintenance Plan: generated option reference (#128)

**Type:** Architectural — new internal tooling layer (docs generated from the
modules), moves the *what* of every option out of hand-written pages.

**Goal:** every visible `stc.relics.*` / `stc.cogitator.*` option is documented
by Markdown generated from the module itself, embedded in its existing page (EN
and FR), and `nix flake check` fails when the committed reference no longer
matches the modules or when an option has no page.

**Why:** 29 pages per language carry a hand-written `## Options` table that
nothing compares with the code. Drift already exists: `relics/heartbeat.md`
says `retries` is `int`, the module declares `ints.unsigned`
(`unsigned integer, meaning >=0`). The only guard today is the namespace grep
in CLAUDE.md, which catches renames, not types, defaults or new options.

**Architecture:** a flake-parts module, `docs/options.nix`, evaluates each
exported module on its own, collects the visible canonical options and renders
one Markdown fragment per declaring source file and per language under
`docs/src/options/{en,fr}/`. The fragments are committed; a check rebuilds them
and diffs. Pages become `.mdx` and import their fragments. Internal tooling, like
`provings/`: nothing is exported to consumers, and no relic or cogitator
changes behaviour. DESIGN.md boundary touched: *Invariant : code et
documentation en synchronisation* — the invariant gains a command that measures
it.

### Measured premises (2026-11-07, locked nixpkgs and home-manager)

- Evaluating all 41 `nixosModules` in one `nixosSystem` fails: several
  cogitators import `inputs.impermanence.nixosModules.impermanence` themselves,
  so `environment.persistence` is declared twice. **One evaluation per
  exported module** works for all 41 NixOS and 7 Home Manager modules; the
  options are then merged by name. Cost: ~75 s NixOS + ~13 s HM.
- 251 `stc.*` NixOS options, 15 HM. The 60 deprecated `stc.*` aliases have
  `visible = false` → excluded by the `visible` filter, no special case.
- Submodule internals `<path>.<name>._module.{args,check,freeformType,specialArgs}`
  come out `visible = true` (declared in nixpkgs `lib/modules.nix`) → excluded
  by name (`hasInfix "._module."`).
- After both filters: **180 options** (173 NixOS, 7 Home Manager), every one
  with a non-empty `description`, every one declared in exactly **one** file,
  **48** distinct declaring files (one is a directory:
  `cogitator/home/enginseer`).
- **One name exists in both classes**: `stc.relics.yubikey.enable` is declared
  by `relics/nixos/yubikey.nix` (NixOS) and `relics/home/yubikey.nix` (HM).
  A merge keyed by name alone silently drops one of them (it did, in a first
  count of 179/47). Options are therefore keyed by **class, then name**, and
  grouped by declaring file — the two land in two different fragments.
- Descriptions are real Markdown: 84 multi-line, 9 with lists, 4 with fenced
  code blocks, 42 with inline code; longest 1744 chars. A table cannot hold
  them → fragments are Markdown sections, not table rows.
- `docs/` has no Markdown renderer as a direct dependency (`@astrojs/markdown-remark`
  is not installed). An `.mdx` page can import a `.md` file and render it as a
  component (`import X from '...md'; <X />`), through Starlight's own Markdown
  pipeline → no new npm dependency. A `.md` import is parsed as Markdown, not
  MDX, so `{` and `<` in descriptions are not JSX.
- `nixosOptionsDoc` fields per option: `type` (string), `default` /
  `example` (`{_type = "literalExpression"; text}` or `literalMD`),
  `description`, `declarations` (store paths → made relative to the flake
  root). 4 defaults are multi-line.
- Page ↔ file mapping, from the option names in today's EN tables (29 pages):
  see *Coverage map* below. 13 files have no table today: the 8
  `relics/nixos/hardening/*.nix`, `relics/home/ghostty.nix`,
  `relics/home/zen-browser.nix`, `relics/nixos/yubikey.nix`,
  `relics/home/yubikey.nix`, `relics/nixos/state.nix`.

### User decisions (2026-11-07)

- Generated and **committed**, with a drift check in `nix flake check`. The
  docs workflow stays Node-only.
- FR pages show the **English** descriptions; only the labels (Type, Default…)
  are translated. The FR prose around them keeps the *why* and the examples.
- The hand-written `## Options` tables are **replaced** in place, not doubled
  by separate reference pages. A coverage check ensures every option's file is
  imported by an EN and an FR page.

### Global Constraints

- No option declaration changes path, type or default. Only `description`
  strings may change (step 3 and 4: text moved from a table into the module).
- Every schematic keeps evaluating; witness drvPaths of
  `schematics/local-vm` qcow2 and `schematics/aws-ami` awsImage unchanged
  (descriptions do not enter a derivation).
- No proving required: no cogitator behaviour changes. `just test` is not
  part of this plan's gates.
- Fragments live outside `docs/src/content/` (otherwise Starlight turns each
  into a page): `docs/src/options/{en,fr}/<slug>.md`, `<slug>` = the declaring
  path with `/` → `-` and `.nix` dropped (`relics/nixos/heartbeat.nix` →
  `relics-nixos-heartbeat`, `cogitator/home/enginseer` →
  `cogitator-home-enginseer`).
- The check and the generator run on `x86_64-linux` only (`checks.x86_64-linux`
  and `legacyPackages.x86_64-linux`): option docs do not depend on the system,
  and other systems would only add evaluation time.
- EN/FR parity kept: every page renamed `.md` → `.mdx` in both languages in the
  same commit (`scripts/check-docs-parity.sh` compares paths).

### Review Focus

- A fragment whose Markdown breaks the page build: `<name>` outside backticks
  becomes an HTML tag, a heading (`#`) inside a description would enter the
  page's TOC. Measured fix lives in the generator, verified by `npm run build`.
- Information silently lost when a table is deleted: a column or note that the
  module description does not carry. Each page step lists what it moved.
- The coverage check accepting a page that imports a fragment but never renders
  it (`import` without `<X />`). The check greps for both.
- `nix flake check` getting slower: +~90 s of evaluation in CI's `check` job.
  Measured in step 1 and reported, not hidden.
- An external consumer: none. No option path, type or default changes; nothing
  new is exported.

### Coverage map (EN page → fragments it must import)

| Page (en/ and fr/) | Fragments |
|---|---|
| `relics/amd-gpu` | `relics-nixos-amd-gpu` |
| `relics/aws` | `relics-nixos-aws` |
| `relics/boot` | `relics-nixos-boot` |
| `relics/docker` | `relics-nixos-docker-crowdsec`, `relics-nixos-docker-guards`, `relics-nixos-docker-notify`, `relics-nixos-docker-socket-proxy`, `relics-nixos-docker-traefik` |
| `relics/hardening` | `relics-nixos-hardening-{kernel,network,filesystem,ssh,modules,scheduler,audit,firewall}`, each under its existing `##` section |
| `relics/heartbeat` | `relics-nixos-heartbeat` |
| `relics/home-apps` | `relics-home-ghostty` (under `## Ghostty`), `relics-home-zen-browser` (under `## Zen Browser`) |
| `relics/impermanence` | `relics-nixos-impermanence` |
| `relics/networking` | `relics-nixos-networking` |
| `relics/nix-housekeeping` | `relics-nixos-nix-housekeeping` |
| `relics/pipewire` | `relics-nixos-pipewire` |
| `relics/plasma-manager` | `relics-home-plasma-manager` |
| `relics/plasma6` | `relics-nixos-plasma6` |
| `relics/polkit-units` | `relics-nixos-polkit-units` |
| `relics/pre-switch-checks` | `relics-nixos-pre-switch-checks` |
| `relics/server-survivability` | `relics-nixos-server-survivability` |
| `relics/smart` | `relics-nixos-smart` |
| `relics/traefik` | `relics-nixos-traefik` |
| `relics/vaultwarden` | `relics-nixos-vaultwarden` |
| `relics/vm-variant` | `relics-nixos-vm-variant` |
| `relics/yubikey` | `relics-nixos-yubikey` (under `## System Relic`), `relics-home-yubikey` (under `## User Relic (Home Manager)`) |
| `relics/zfs` | `relics-nixos-zfs` |
| `reference/state-manifest` | `relics-nixos-state` |
| `cogitator/desktop` | `cogitator-home-desktop` |
| `cogitator/docker-server` | `cogitator-nixos-docker-server` (its table also lists docker relic options: those rows go, the page links to `relics/docker`) |
| `cogitator/dreadnought` | `cogitator-nixos-dreadnought` |
| `cogitator/enginseer` | `cogitator-home-enginseer` |
| `cogitator/gaming` | `cogitator-nixos-gaming` |
| `cogitator/hardening` | `cogitator-nixos-hardening` |
| `cogitator/plasma` | `cogitator-nixos-plasma` |
| `cogitator/sarcophagus-aws` | `cogitator-nixos-sarcophagus-aws` |
| `cogitator/sarcophagus-kvm` | `cogitator-nixos-sarcophagus-kvm` |
| `cogitator/vm` | `cogitator-nixos-vm` |
| `cogitator/workstation` | `cogitator-nixos-workstation` |

The map lists 48 fragments. Step 1 prints the generated slug list; any slug
not in this map is added to it in the ledger before step 2 (a ruling, not a
stall).

### Affected Files

- [ ] `docs/options.nix` (new) — generator, check
- [ ] `flake.nix` — import `./docs/options.nix`
- [ ] `Justfile` — `options-doc` recipe
- [ ] `docs/src/options/en/*.md`, `docs/src/options/fr/*.md` (generated, committed)
- [ ] the 34 pages of the coverage map, `en/` and `fr/`, `.md` → `.mdx`
- [ ] `relics/**/*.nix`, `cogitator/**/*.nix` — `description` strings only, where a table carried more
- [ ] `CLAUDE.md` (*Adding a new relic* step 4, *Adding a new cogitator* step 5)
- [ ] `PROCEDURE_PLANS.md` (*Adding a New Relic* doc template, Gate 4)
- [ ] `DESIGN.md` (*Invariant : code et documentation* — name the check)

### Atomic Steps

#### Step 1: Generator, committed fragments, drift check

**Description:** `docs/options.nix` is a flake-parts module. In `perSystem`,
guarded by `lib.optionalAttrs (system == "x86_64-linux")`:

- `optionDocs` — for each `self.nixosModules.<n>`:
  `lib.nixosSystem { inherit system; modules = [ m base ]; }` with
  `base = { system.stateVersion = "25.11"; boot.loader.grub.enable = false; fileSystems."/".device = "none"; }`;
  for each `self.homeModules.<n>`:
  `inputs.home-manager.lib.homeManagerConfiguration { inherit pkgs; modules = [ m hbase ]; }`
  with `hbase = { home.username = "doc"; home.homeDirectory = "/home/doc"; home.stateVersion = "25.11"; }`.
  `lib.optionAttrSetToDocList` on each `.options`, keep
  `o.visible && !(lib.hasInfix "._module." o.name) && (lib.hasPrefix "stc.relics." o.name || lib.hasPrefix "stc.cogitator." o.name)`,
  key by class then name (`{ nixos = { <name> = o; }; home = { <name> = o; }; }`,
  `lib.listToAttrs` within each class — never across). Assertion (`throw`) if an option has
  zero or several declarations, or an empty description — the premises above,
  turned into guards.
- Grouping by `lib.removePrefix "${self}/" (toString (head o.declarations))`.
- Rendering, per option, sorted by name, labels from
  `{ en = { type = "Type"; default = "Default"; example = "Example"; declared = "Declared in"; }; fr = { type = "Type"; default = "Valeur par défaut"; example = "Exemple"; declared = "Déclarée dans"; }; }`:

  ````markdown
  #### `stc.relics.heartbeat.retries`

  curl retries for a failed ping.

  - **Type:** unsigned integer, meaning >=0
  - **Default:** `3`
  - **Declared in:** [`relics/nixos/heartbeat.nix`](https://github.com/gfriloux/stc/blob/main/relics/nixos/heartbeat.nix)
  ````

  A multi-line default or example is a fenced ` ```nix ` block on the lines
  after its label. No default → the line is omitted. `literalMD` text is
  inserted as-is. Each file starts with
  `<!-- Generated by docs/options.nix — run \`just options-doc\`, do not edit. -->`.
- `legacyPackages.options-doc` — `pkgs.linkFarm` / `runCommand` producing
  `en/<slug>.md` and `fr/<slug>.md`.
- `checks.options-doc` — `runCommand` running
  `diff -r ${legacyPackages.options-doc} ${self}/docs/src/options`; on failure
  it prints `run: just options-doc`.

`Justfile`:

```just
# Regenerate the option reference fragments from the modules (docs/src/options).
options-doc:
    rm -rf docs/src/options
    cp -r --no-preserve=mode "$(nix build --no-link --print-out-paths .#legacyPackages.x86_64-linux.options-doc --no-write-lock-file)" docs/src/options
```

**Files changed:** `docs/options.nix`, `flake.nix`, `Justfile`,
`docs/src/options/**`

**Interfaces:**
- Produces: `legacyPackages.x86_64-linux.options-doc`,
  `checks.x86_64-linux.options-doc`, `just options-doc`, the 48×2 fragment
  paths `docs/src/options/{en,fr}/<slug>.md`.

**Verification command(s):**
```bash
just options-doc && ls docs/src/options/en | wc -l          # 48
grep -l 'stc.relics.yubikey.enable' docs/src/options/en/*  # relics-nixos-yubikey.md AND relics-home-yubikey.md
nix flake check --no-write-lock-file                        # green, time noted
# drift: edit one description, check must fail, revert
sed -i 's/curl retries for a failed ping./X./' relics/nixos/heartbeat.nix
nix build .#checks.x86_64-linux.options-doc --no-write-lock-file   # fails
git checkout relics/nixos/heartbeat.nix
```

**Commit message:** `feat(docs): generate the option reference from the modules`

---

#### Step 2: First page — heartbeat, end to end

**Description:** `en/relics/heartbeat.md` and `fr/relics/heartbeat.md` →
`.mdx` (`git mv`). The `## Options` table is replaced by:

```mdx
import Options from '../../../../options/en/relics-nixos-heartbeat.md';

## Options

<Options />
```

(`fr` imports `.../options/fr/...`). The table's extra text — the `<name>`
note on `units.<name>.urlFile` and the `packageUnit` explanation — is compared
with the module descriptions; anything missing is moved into the `description`
in `relics/nixos/heartbeat.nix`, then `just options-doc`.

**Files changed:** the two pages, `relics/nixos/heartbeat.nix` (descriptions
only, if needed), `docs/src/options/**`

**Interfaces:**
- Consumes: `docs/src/options/{en,fr}/relics-nixos-heartbeat.md` (step 1).

**Verification command(s):**
```bash
nix develop .#docs --command bash -c 'cd docs && npm ci && npm run build'
grep -c 'stc.relics.heartbeat.retries' docs/dist/relics/heartbeat/index.html docs/dist/fr/relics/heartbeat/index.html   # ≥1 each
grep -c 'unsigned integer' docs/dist/relics/heartbeat/index.html                      # ≥1: the real type now shows
bash scripts/check-docs-parity.sh
nix build .#checks.x86_64-linux.options-doc --no-write-lock-file
```

**Commit message:** `docs(relics): heartbeat options from the generated reference`

---

#### Step 3: Remaining relic pages

**Description:** same transformation as step 2 for every `relics/*` and
`reference/state-manifest` row of the coverage map, EN and FR. Pages with a
table: the table goes, the import takes its place. Pages without one
(`hardening`, `home-apps`, `yubikey`, `state-manifest`): the import goes at the
end of the matching `##` section named in the map, under an `### Options`
heading. For each page, the ledger gets one line: what the table carried that
the descriptions did not, and where it went.

**Files changed:** 21 relic pages (all but heartbeat) + `reference/state-manifest`, ×2 languages;
`relics/**/*.nix` descriptions; `docs/src/options/**`

**Interfaces:**
- Consumes: every `relics-*` fragment of step 1.

**Verification command(s):**
```bash
nix develop .#docs --command bash -c 'cd docs && npm run build'
bash scripts/check-docs-parity.sh
nix build .#checks.x86_64-linux.options-doc --no-write-lock-file
grep -rln '^| `stc\.relics\.' docs/src/content/docs        # empty: no hand table left
```

**Commit message:** `docs(relics): option tables from the generated reference`

---

#### Step 4: Cogitator pages

**Description:** same for the 11 `cogitator/*` pages. `cogitator/docker-server`'s
table rows for `stc.relics.docker.*` options are removed and replaced by a
sentence linking `relics/docker` (EN: "Relic options: see [Docker relics](../../relics/docker/)."; FR: "Options des reliques : voir [Reliques Docker](../../relics/docker/).").

**Files changed:** 11 cogitator pages ×2; `cogitator/**/*.nix` descriptions;
`docs/src/options/**`

**Interfaces:**
- Consumes: every `cogitator-*` fragment of step 1.

**Verification command(s):**
```bash
nix develop .#docs --command bash -c 'cd docs && npm run build'
bash scripts/check-docs-parity.sh
nix build .#checks.x86_64-linux.options-doc --no-write-lock-file
grep -rln '^| `stc\.cogitator\.' docs/src/content/docs      # empty
```

**Commit message:** `docs(cogitator): option tables from the generated reference`

---

#### Step 5: Coverage check and the written rules

**Description:** `checks.options-doc` gains a coverage pass: for each slug,
`grep -rlq "options/en/<slug>.md'" ${self}/docs/src/content/docs/en` **and**
the `fr` equivalent must match, and each matching page must also contain
`<` + the imported identifier + ` />`. Missing → fail with the slug and
`import it from its page (en and fr)`.

Rules updated in the same commit:
- `CLAUDE.md` *Adding a new relic* step 4 and *Adding a new cogitator* step 5:
  "…a bilingual doc page (`.mdx`) that imports its generated options from
  `docs/src/options/{en,fr}/<slug>.md`; run `just options-doc`."
- `PROCEDURE_PLANS.md` *Adding a New Relic* doc template: the `## Options`
  table example becomes the import; Gate 4 lists
  `nix build .#checks.x86_64-linux.options-doc`.
- `DESIGN.md` *Invariant : code et documentation en synchronisation*: one
  paragraph — the options reference is generated, `checks.options-doc` measures
  both drift and coverage.

**Files changed:** `docs/options.nix`, `CLAUDE.md`, `PROCEDURE_PLANS.md`,
`DESIGN.md`

**Interfaces:**
- Consumes: the import lines written in steps 2–4.

**Verification command(s):**
```bash
nix build .#checks.x86_64-linux.options-doc --no-write-lock-file    # green
# negative: drop one import from an fr page → check fails naming the slug, revert
nix flake check --no-write-lock-file
```

**Commit message:** `feat(docs): fail when an option has no page`

### Quality Gates

- [ ] `nix flake check --all-systems --no-build --no-write-lock-file` and `nix flake check --no-write-lock-file` pass
- [ ] Schematics evaluate, drvPaths unchanged:
  - [ ] `nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file`
  - [ ] `nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file`
- [ ] `just fmt-check lint`
- [ ] Docs build: `nix develop .#docs --command bash -c 'cd docs && npm run build'`
- [ ] Doc parity: `bash scripts/check-docs-parity.sh`
- [ ] Namespace grep from CLAUDE.md (now including `.mdx`): no stale reference
- [ ] One fresh-context review at branch close (PROCEDURE_PLANS.md *Closing review*)
- [ ] All commits atomic and signed
