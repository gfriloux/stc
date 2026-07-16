# PLAN_PROVINGS.md — Maintenance Plan: The Provings (nixosTest pillar)

> Plan issu de la comparaison STC vs Sécurix/Bureautix (DINUM). Roadmap plan 1/4.
> À valider avant tout code. Suit le template de `PROCEDURE_PLANS.md`.

## Maintenance Plan: Introduce the `provings/` pillar + first hardening test

**Type:** New root pillar (structural) + first nixosTest

**Objective:** Doter STC de tests de *comportement* (`nixosTest`) qui bootent une
VM et vérifient qu'un cogitator fait réellement ce qu'il prétend — en commençant
par `cogitator-hardening`. Aujourd'hui STC n'a que de la vérification statique
(`nix flake check` = « ça évalue »), jamais « ça marche ».

**Why:** C'est l'écart le plus rentable identifié face à Sécurix, qui a un dossier
`tests/` avec le framework de tests NixOS. Un durcissement non testé est un
durcissement supposé.

**Nommage :** `provings/` — thème Adeptus Mechanicus (« The Rite of Proving » :
prouver que le machine spirit répond correctement), cohérent avec relics /
cogitator / forge / rites. On *prouve* qu'un cogitator fonctionne.

### Décisions actées (2026-07-04)

1. **Nouveau pilier `provings/`** (6e répertoire racine), sanctionné par DESIGN.md,
   au même titre que `schematics/` (top-level, documenté, statut particulier
   vis-à-vis des outputs).
2. **Exposition via `legacyPackages.<system>.provings.*`** — `nix flake check`
   **ignore délibérément** `legacyPackages`. Les provings sont donc **hors gate**
   `just ci` / Purity Seals, conformément à la décision « manuel pour le moment ».
3. **Lancement manuel via `just test`** (`nix build .#legacyPackages…provings.*`).
4. **Linux uniquement** — les VM tests n'ont de sens que sur `x86_64-linux`
   (et éventuellement `aarch64-linux`). Le wiring garde `provings` vide sur Darwin.

### Affected Files

- [ ] `DESIGN.md` — ajouter le pilier `provings/` (5 piliers → 6)
- [ ] `flake.nix` — ajouter `./provings` aux `imports`
- [ ] `provings/default.nix` — module flake-parts, expose `legacyPackages.<system>.provings.*`
- [ ] `provings/hardening.nix` — le nixosTest du cogitator hardening
- [ ] `Justfile` — recette `test` (hors `ci`)
- [ ] `docs/src/content/docs/en/…` — page du pilier provings
- [ ] `docs/src/content/docs/fr/…` — idem (parité obligatoire)

---

### Atomic Steps

#### Step 1: Sanctionner le pilier `provings/` dans DESIGN.md

**Description :** Amender la section « Les cinq piliers » → six. Définir ce qui
appartient à `provings/` : les nixosTests **internes** de STC (QA de comportement),
pas des artefacts consommateurs. Préciser le statut vis-à-vis des outputs :
exposés en `legacyPackages`, donc **hors `nix flake check`**, lancés par
`just test`. Distinguer explicitement de `forge/purity-seals/` (qui, lui, produit
des *builders de checks* pour les flakes consommateurs).

**Files changed:**
- `DESIGN.md`

**Verification command(s):**
```bash
# Revue humaine : cohérence avec le reste de DESIGN.md. Pas de build.
grep -n "provings" DESIGN.md
```

**Commit message:** `docs(design): sanction the provings/ pillar for nixosTests`

---

#### Step 2: Scaffolder `provings/` + le test hardening + le wiring

**Description :** Créer le pilier et son premier test en un seul commit
(un pilier vide ne serait pas indépendamment testable).

- `provings/hardening.nix` : module de test consommé par `pkgs.testers.runNixOSTest`.
  Un nœud `machine` importe `self.nixosModules.cogitator-hardening` et active
  `stc.cogitator.hardening.enable = true`. Le `testScript` **assert** le
  comportement réel (voir « Assertions » plus bas).
- `provings/default.nix` : module flake-parts. Dans `perSystem`, sur Linux
  uniquement, expose :
  `legacyPackages.provings.hardening = pkgs.testers.runNixOSTest (import ./hardening.nix { inherit self; });`
  (accès à `self` via les args du module flake-parts — pattern inputs closure).
- `flake.nix` : ajouter `./provings` à `imports`.

**Assertions du test hardening (contrat de comportement) :**
- *kernel* : `sysctl -n kernel.kptr_restrict` = 2 ; `kernel.randomize_va_space` = 2 ;
  `kernel.unprivileged_bpf_disabled` = 1 ; `kernel.yama.ptrace_scope` = 1 ;
  `fs.suid_dumpable` = 0.
- *network* : `net.ipv4.tcp_syncookies` = 1 ; `net.ipv4.conf.all.rp_filter` = 1 ;
  `net.ipv4.conf.all.accept_redirects` = 0.
- *filesystem* : `findmnt -no OPTIONS /tmp` contient `noexec` ; `/dev/shm` contient
  `noexec` ; `/proc` monté avec `hidepid=2`.
- *ssh* : `sshd -T` renvoie `passwordauthentication no` et `permitrootlogin no` ;
  le service `sshd` démarre.

> Note : le test parle à la VM par la backdoor du framework (console root), pas par
> SSH — le durcissement SSH (no password, keys only) n'empêche donc pas le test.
> Le relic SSH exige OpenSSH ≥ 9.9 : OK sur `nixos-unstable`.

**Files changed:**
- `provings/hardening.nix`
- `provings/default.nix`
- `flake.nix`

**Verification command(s):**
```bash
# Le test doit RÉELLEMENT tourner (build = run de la VM) :
nix build .#legacyPackages.x86_64-linux.provings.hardening -L --no-write-lock-file

# Le gate NE doit PAS lancer le test (legacyPackages ignoré) et rester vert :
nix flake check --no-write-lock-file

# deadnix/statix sur le nouveau code :
just lint
```

**Commit message:** `test(provings): add hardening nixosTest and provings pillar wiring`

---

#### Step 3: Recette `just test` (hors gate)

**Description :** Ajouter une recette `test` au Justfile, séparée de `ci`.
Ne PAS l'ajouter à la cible `ci` (`fmt-check lint check docs-parity`) — décision
« hors gate ». Commentaire explicite indiquant que c'est lourd et manuel.

**Files changed:**
- `Justfile`

**Verification command(s):**
```bash
just test        # doit builder/lancer provings.hardening
just --list      # 'test' visible, 'ci' inchangé
```

**Commit message:** `build(just): add manual 'test' recipe to run the provings`

---

#### Step 4: Documenter le pilier `provings/` (EN + FR)

**Description :** Page de doc bilingue expliquant : ce qu'est un proving, pourquoi
il est hors gate, comment le lancer (`just test`), et comment en ajouter un.
Respecte l'invariant DESIGN.md « code et doc dans le même changement » et la
parité EN/FR.

**Files changed:**
- `docs/src/content/docs/en/<section>/provings.md` (emplacement exact à confirmer :
  section dédiée `provings/` ou sous `forge/`/contributing — à trancher en Step 4)
- `docs/src/content/docs/fr/<section>/provings.md`

**Verification command(s):**
```bash
just docs-parity
cd docs && npm run astro check
```

**Commit message:** `docs(provings): document the provings pillar (EN + FR)`

---

### Quality Gates

- [ ] `nix flake check --no-write-lock-file` passe **et** ne lance pas les provings
- [ ] `nix build .#legacyPackages.x86_64-linux.provings.hardening -L` : test **vert**
- [ ] `just test` fonctionne ; `just ci` inchangé (provings absents du gate)
- [ ] `just lint` propre (deadnix/statix sur `provings/`)
- [ ] Parité doc EN/FR : `just docs-parity`
- [ ] Chaque commit est atomique et vérifiable indépendamment

### Suites (hors de ce plan, roadmap plan 1)

Une fois le pattern validé sur hardening, répliquer un proving par cogitator, un
commit chacun : `docker-server`, puis `vm` / `sarcophagus`. Même wiring, nouvelles
entrées `legacyPackages.<system>.provings.<nom>`.
