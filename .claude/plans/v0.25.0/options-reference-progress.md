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
Step 2: Ruling: the built pages live under `docs/dist/en/…`, not `docs/dist/…` —
the plan's grep paths were wrong, steps 3–5 use `docs/dist/en/` — cost if wrong:
none, a missing file makes grep fail loudly.
Step 2: no description moved — the module already carried the `<name>` and
`packageUnit` notes the table held.
Step 2: complete (docs build OK, 104 pages; `retries` in EN and FR pages; `unsigned integer` shown; parity OK; checks.options-doc → OK).
Step 3: Ruling: an option with no default renders "Default: *none, must be set*"
(FR "*aucune, à définir*") — the tables' **Required** marks had no counterpart;
all 12 such options are ones the consumer must set (aws.poolName, traefik.email,
the docker image/dataDir/email options, heartbeat urlFile, polkit group, state
paths fields, vaultwarden.hostname, zfs autoSnapshot.poolName) — cost if wrong:
a future option without default that is not required would be mislabelled;
the label is one line of the generator.
Step 3: Ruling: `hardening` and `home-apps` do have tables (the plan said not):
they go like any other; only the kernel section has none and gets the
`**Options:**` label + component the other hardening sections use. Yubikey:
`### Options` at the end of each `##` relic section. State manifest: a
`## Options` section before `## Proving` (the map named no section).
Step 3: Ruling: multi-fragment pages name each component after its slug
without `relics-` (`NixosDockerTraefikOptions`); single-fragment pages keep
`Options` — cost if wrong: none, names are page-local.
Step 3: moved from tables — polkit-units: "(also enables polkit)" → enable
option text; group "must exist in users.groups" → its description.
nix-housekeeping: optimise "skipped in a container" → description.
hardening-ssh: allowedTCPForwarding "also drives StreamLocalBindUnlink" →
description. docker guards: "true in cogitator-docker-server" → page prose
(EN/FR), it is the cogitator's mkDefault, not the relic's. zfs: `<poolName>`
put in backticks (rendered as an HTML tag otherwise). Every other row was
covered by the module description (compared row by row).
Step 3: complete (docs build OK, 104 pages; per page rendered h4 count = fragment option count; parity OK; no `| \`stc.relics.` table left outside cogitator/docker-server (step 4); fmt-check + lint OK; nix flake check → exit 0 incl. options-doc).
Step 4: Ruling: cogitator/docker-server's relic rows are not in its Options
table but in a separate "Required Options" checklist (`| Option | Why |`, no
type, no default) — it stays: it tells what the consumer must set for this
profile, which no fragment says; only tables with a Type column are replaced.
Step 3's leftover grep therefore keeps matching that page, by design — cost if
wrong: a renamed relic option leaves a stale name in the checklist; the
namespace-migration doc grep already covers `docs/`.
Step 4: no description moved — every cogitator table row was covered by its
module description (compared row by row).
Step 4: complete (docs build OK, 104 pages; rendered h4 = fragment option count on all 22 pages; parity OK; no `| \`stc.cogitator.` table left; checks.options-doc → OK).
Step 5: coverage pass added to checks.options-doc — each slug must be imported
*and* rendered (`<Name />`) by a page in en/ and in fr/. Negatives measured:
render line dropped from fr/relics/boot → "fr: no page renders
options/fr/relics-nixos-boot.md"; import line dropped from en/relics/boot →
"en: no page renders …"; both reverted.
Step 5: rules updated — CLAUDE.md (new relic step 4, new cogitator step 5),
PROCEDURE_PLANS.md (relic doc template → `.mdx` + `<Options />`, Gate 4 lists
checks.options-doc), DESIGN.md (sync invariant: the reference is generated).
Step 5: Quality gates — `nix flake check --all-systems --no-build` → 0;
`nix flake check` → 0; fmt-check + lint → 0; parity OK; schematic drvPaths
identical to main with `--override-input stc` (local-vm 6w83sj19…,
aws-ami 6cfzl6gi…); namespace grep: the only `.mdx` hits are `stc.inputs.*`
flake-input references, present before this branch; docs build last run at
step 4 on identical page content.
Step 5: complete.
Closing review (fresh context) — triage:
- Fixed: docker-notify `hostname` rendered the doc evaluation's `"nixos"` —
  `defaultText` added; generator now evaluates with a sentinel host name and
  home and throws when a default/example holds one or a store path (measured:
  without the `defaultText` the build fails naming the option).
- Fixed: indented blocks in 7 descriptions (3 docker image pins, notify and
  smart variable lists, smart default directives, notify watch label) ran into
  prose with curly quotes — pins in ```nix fences (line unchanged), lists as
  `- ` bullets. Rendered HTML checked: `<li><code>STC_NOTIFY_SERVICE`, pin in
  `<pre>`, no curly-quoted image left.
- Fixed: coverage reads `.mdx` only, requires the whole line `<Name />`,
  accepts digits/underscore in names; duplicate slugs throw explicitly.
- Fixed: `just options-doc` builds before it removes anything.
- Fixed: label → "none, required when used" (FR "aucune, requise à
  l'usage"): these options are required only once their relic or entry is in
  use. Types render in backticks. strictArp's "`../nixos`" → "the
  docker-server cogitator".
- Kept, ruling: fragments use `####` under `## Options` (h2 → h4): h4 keeps
  180 option names out of Starlight's on-page TOC (h2–h3) — cost if wrong: a
  heading-level lint complaint, none runs today.
- Kept, ruling: a `<Name />` inside a code fence would still count as
  rendered — no page shows MDX components in fences; cost if wrong: one false
  pass the docs build would not catch.
Review fixes verified: docs build OK (104 pages), fmt-check + lint OK, parity OK, nix flake check → 0.
PR #147 CI: `check` job cancelled during `--all-systems --no-build`, no Nix
error, 75 s of silence — the runner ran out of memory. Measured locally
(peak RSS of `nix flake check --all-systems --no-build`): main 11.7 GiB,
branch 16.1 GiB (GitHub runner: 16 GB). Walking only `options.stc`: 15.8 GiB —
not the cause. Cause: ~45 NixOS/HM evaluations, one per exported module.
Ruling: one evaluation per class over STC's own files (paths unwrapped from
the flake-parts and STC wrappers) plus each upstream module once, listed
explicitly in `upstream` — the function-valued upstream modules cannot be
deduplicated by the module system, and Nix's pointer equality does not hold
for them (measured `false`). Peak now 12.6 GiB, 155 s; fragments
byte-identical (checks.options-doc green without regeneration) — cost if
wrong: a new upstream module missing from the list fails the evaluation
loudly once an STC file sets one of its options.
