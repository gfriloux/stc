# Plan: documentation toolchain — Astro 5 → 7, Starlight 0.33 → 0.41

**Type:** project infrastructure (documentation toolchain; no relic/cogitator behaviour change)

**Objective:** Bring the Starlight documentation site onto Astro v7 and
`@astrojs/starlight` 0.41, with a regenerated `package-lock.json` and a build
verified locally.

**Why:**
- Renovate opened `#14` (starlight `^0.33.0` → `^0.41.0`) and `#15` (astro
  `^5.7.0` → `^7.0.0`) as two independent PRs. **Neither can be merged alone**:
  `@astrojs/starlight@0.41.7` declares `peerDependencies: { astro: "^7.0.2" }`,
  so each PR on its own produces an unresolvable dependency graph. This is
  exactly why the `renovate/artifacts` check failed on both — Renovate could not
  regenerate the lockfile.
- Both PRs therefore carried a modified `package.json` with a **stale
  `package-lock.json`**.
- `.github/workflows/docs.yml` only runs on `push` to `main` (`paths: docs/**`),
  never on pull requests. Merging either PR would have broken the GitHub Pages
  deploy directly on `main`, with no prior signal. The build must be verified
  locally.
- `#18` (npm lock file maintenance) sat on the abandoned Astro 5 line and was
  closed as superseded by this work.

**Branch:** `chore/docs-astro7` (the user merges; Claude never merges/pushes/tags).

**Scope:** everything under `docs/`. No Nix code, no relic, no cogitator, no
schematic is touched — the flake is untouched by this plan.

---

## Decisions

- **One upgrade, not two.** The peer constraint makes astro and starlight a
  single atomic unit. `#14` and `#15` are superseded by this branch and are
  closed rather than rebased.
- **Plan filed under `release/`**, not `vX.Y.Z/`: this is documentation tooling
  infrastructure, not a product feature. Note that the commits *do* reach the
  changelog — `cliff.toml` orders `^chore\(deps\)` (group *Dependencies*) before
  the `^chore` skip rule, and `^docs` has its own *Documentation* group — so they
  will appear under whichever tag ships next.
- **Content Layer migration is split out first.** It is valid on the *current*
  Astro 5 as well as on 7, so it can be committed and verified independently,
  shrinking the surface of the version-bump commit.
- **The version bump stays one commit.** `package.json`, `package-lock.json` and
  the `astro.config.mjs` sidebar restructure cannot be separated: any one of them
  alone leaves the site unbuildable, which would violate Gate 5 (every commit
  independently verifiable).

---

## Breaking changes that actually hit this repository

Established from the Astro v6 and v7 upgrade guides and the Starlight changelog
for 0.34 → 0.41. Two majors of Astro are crossed at once (v6 is skipped).

### Hard blockers — the build fails without these

| # | Origin | What breaks here |
|---|--------|------------------|
| 1 | Astro 6 — legacy content collections removed | `docs/src/content/config.ts` sits at the **legacy** path and has no `loader`. Must become `docs/src/content.config.ts` using `docsLoader()`. |
| 2 | Starlight 0.39 — `autogenerate` must be nested | All **six** sidebar groups in `astro.config.mjs` use `autogenerate: { directory: … }` directly on the group. Each must be wrapped in `items: [{ autogenerate: … }]`. |
| 3 | Starlight 0.39 — subgroups no longer inherit `collapsed` | The three groups declaring `collapsed: true` (Schematics, Provings, Reference) must repeat it as `autogenerate: { directory: …, collapsed: true }`. The directories are currently flat, so this is defensive rather than observable today — but it encodes the intent. |

### Requires verification, may require a fix

| # | Origin | Risk here |
|---|--------|-----------|
| 4 | Starlight 0.34 — all Starlight CSS moved into a `starlight` cascade layer | `docs/src/styles/stc.css` is 429 lines of **unlayered** custom CSS. Unlayered rules now beat layered ones unconditionally. The known `.sl-markdown-content table { display: table }` override (line 336) will still win; the risk is the reverse — custom rules that previously *lost* to Starlight now silently win. Highest visual-regression risk of the whole upgrade. |
| 5 | Astro 7 — Rust compiler, stricter HTML | `Hero.astro` and `pages/index.astro` were read and are well-formed. The two `index.mdx` splash pages still need to pass the new parser. |
| 6 | Astro 7 — `compressHTML` default `true` → `'jsx'` | Can drop spaces between inline elements. Affects rendered prose across 84 content pages. |
| 7 | Astro 7 — Markdown processor is now Sätteri | No `markdown:` key in `astro.config.mjs` and no remark/rehype plugin of our own, so nothing to port. But Starlight 0.41 still declares `@astrojs/markdown-remark ^7.2.0` as a peer — confirm what npm resolves. |
| 8 | Astro 6 — heading IDs keep trailing hyphens | In-page anchors pointing at headings ending in a special character would shift. Needs a grep over the content tree. |
| 9 | Starlight 0.37 — `overflow-wrap: break-word` on prose elements | Table and heading wrapping changes. Cosmetic, interacts with #4. |

### Verified as *not* affecting this repository

- **Starlight 0.36 — `meta` head entries with `content` are now an error.** The
  four `head` entries in `astro.config.mjs` are `link` and `script` tags and all
  use `attrs`. Clean.
- **Astro 6 — Zod 4.** `content/config.ts` imports no `z`; only `docsSchema()`.
- **Astro 6/7 — removed APIs** (`ViewTransitions`, `Astro.glob()`, `@astrojs/db`,
  `astro:transitions` internals, `src/fetch.ts`): none present.
- **`Astro.locals.starlightRoute`**, used by `Hero.astro`, is still the current
  API in 0.41 (the 0.39 changelog documents its `sidebar` shape).
- **Node.** Astro 7 needs `>= 22.12.0`. The `.#docs` dev shell provides
  **v24.15.0**, and CI moved to Node 24 when `#16` merged. Nothing to change.

---

## Atomic steps

### Step 1 — Migrate content collections to the Content Layer API

**Description:** Move the collection definition off the legacy path and give it
an explicit loader. Valid on Astro 5, and mandatory from Astro 6.

**Files changed:**
- `docs/src/content/config.ts` → deleted
- `docs/src/content.config.ts` → created

```js
import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
};
```

**Verification** (still on Astro 5 / Starlight 0.33 — proves the step in isolation):
```bash
nix develop .#docs --command bash -c 'cd docs && npm ci && npm run astro check && npm run build'
```

**Commit:** `refactor(docs): migrate content collections to the Content Layer API`

---

### Step 2 — Upgrade Astro to v7 and Starlight to 0.41

**Description:** Bump both packages together, regenerate the lockfile, and apply
the sidebar restructure that Starlight 0.39 requires. Indivisible: any subset
leaves the site unbuildable.

**Files changed:**
- `docs/package.json` — `astro: ^7.0.0`, `@astrojs/starlight: ^0.41.0`
- `docs/package-lock.json` — regenerated (`npm install`, not hand-edited)
- `docs/astro.config.mjs` — six sidebar groups rewritten:

```diff
 {
   label: 'Reference',
   translations: { fr: 'Référence' },
   collapsed: true,
-  autogenerate: { directory: 'reference' },
+  items: [{ autogenerate: { directory: 'reference', collapsed: true } }],
 }
```

**Verification:**
```bash
nix develop .#docs --command bash -c 'cd docs && npm install && npm run astro check && npm run build'
```

**Commit:** `chore(deps): upgrade astro to v7 and starlight to 0.41`

---

### Step 3 — Repair whatever the upgrade actually broke

**Description:** Only exists if Steps 1–2 surface a real regression. Each fix is
its own commit, scoped to what broke, in this order of likelihood: cascade-layer
fallout in `stc.css` (#4), inline-spacing from `compressHTML` (#6), MDX parsing
under the Rust compiler (#5), shifted heading anchors (#8).

**Verification:** full build, plus a render check of the splash page, a sidebar
group of each collapsed state, and a page containing a table.

**Commit:** `fix(docs): <what broke>` — one per regression, or omitted entirely.

---

## Quality gates

The Nix gates are listed for completeness; this branch touches no `.nix` file, so
they should be unaffected — which is itself worth confirming once.

- [ ] `nix flake check --no-write-lock-file` passes
- [ ] Schematics still evaluate (untouched, but cheap to confirm):
  - [ ] `nix eval ./schematics/local-vm#…qcow2.drvPath --no-write-lock-file`
  - [ ] `nix eval ./schematics/aws-ami#…awsImage.drvPath --no-write-lock-file`
  - [ ] `nix eval ./schematics/dreadnought#…toplevel.drvPath --no-write-lock-file`
- [ ] `npm run astro check` reports no type error
- [ ] `npm run build` completes and emits `docs/dist`
- [ ] `bash scripts/check-docs-parity.sh` passes (en/fr trees)
- [ ] `package.json` and `package-lock.json` agree — `npm ci` succeeds from clean
- [ ] Rendered output inspected: splash hero, collapsed *and* expanded sidebar
      groups, a page with a table, an aside, a code block
- [ ] No stale namespace references introduced in docs (Gate 4 grep)
- [ ] Every commit is atomic and independently buildable

## Outcome

Executed in two commits; **Step 3 was not needed** — nothing broke.

- `f853c02` — Content Layer migration, verified on Astro 5 first: 86 pages,
  84 indexed, 6236 words, identical to baseline.
- `b8dd64d` — Astro 7.2.0 / Starlight 0.41.7. `npm install` first failed with
  `ERESOLVE` against the stale lock, reproducing the exact `renovate/artifacts`
  failure; the lockfile had to be regenerated from scratch.

Every risk listed above was resolved rather than merely surviving the build:

- **#4 cascade layer** — Starlight's CSS lands in `@layer starlight.{reset,base,
  core,components,content,utils}`; `stc.css` stays unlayered and therefore wins
  unconditionally. All 13 Starlight class hooks it targets still exist in the
  0.41 markup, so nothing detached silently. Confirmed visually on the built
  artefact (`docs-preview`, not `docs-dev` — the dev server's unbundled CSS
  ordering would not have tested the real cascade).
- **#5 Rust compiler** — both `index.mdx` splash pages parse; the custom Hero
  renders with `Astro.locals.starlightRoute` and its extra `eyebrow` frontmatter.
- **#6 `compressHTML`** — an automated diff of rendered text against source
  across 41 EN pages found 7 candidate glued words, all false positives
  (`filesystem`, `nixosModules`, `pulseaudio`… — real identifiers inside code).
- **#7 Sätteri** — npm resolves `@astrojs/markdown-remark@7.2.2` under Starlight;
  nothing to port.
- **#8 heading IDs** — the documentation contains **zero** in-page anchors, so the
  trailing-hyphen change cannot bite.

The Nix gates confirm the flake was untouched: all three schematic `drvPath`
values are byte-identical to those produced on `#17`.

Two gaps found while executing, both pre-existing and deliberately left out of
this branch:

- `npm run astro check` — the Gate 4 command in `PROCEDURE_PLANS.md` — has never
  been runnable here. `docs/package.json` declares no `astro` script, and
  `@astrojs/check` / `typescript` are not dependencies. `npm run build` is the
  gate that actually holds.
- The `docs-*` Justfile recipes silently assume the `.#docs` shell and fail with
  `npm: command not found` from the default shell.

## Follow-up

Once merged, `#14` and `#15` are closed as superseded. Worth considering
separately: `docs.yml` never builds the site on a pull request, which is what let
these two PRs look green while being unbuildable. Adding a build job on PRs
touching `docs/**` would close that hole — out of scope here, but the reason this
plan needed to exist.
