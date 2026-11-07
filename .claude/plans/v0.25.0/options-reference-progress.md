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
