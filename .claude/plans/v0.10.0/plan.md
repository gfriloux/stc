# Plan v0.10.0 — Relique `hardening.scheduler` : restreindre cron et at à une liste explicite

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Adding a New Relic*.
> Travail atomique, une branche, doc synchronisée dans le même commit.
>
> **Branche :** `feat/hardening-scheduler-allowlist` — **Issue :** [#39](https://github.com/gfriloux/stc/issues/39)

---

## Type

Adding a relic (architectural — nouvelle relique, donc plan file).

## Objectif

Livrer `stc.relics.hardening.scheduler` : quand un ordonnanceur classique
(`services.cron`, `services.atd`) est actif sur la machine, l'accès y est
restreint à une liste d'utilisateurs explicite, `["root"]` par défaut.

## Pourquoi

L'issue #39 part des règles CIS ~2.4.1.x. L'analyse préalable a corrigé deux
erreurs de prémisse et dégagé un argument qui, lui, tient :

1. **Les chemins de l'issue n'existent pas sur NixOS.** Vixie-cron utilise
   `/var/cron/cron.{allow,deny}` et non `/etc/cron.{allow,deny}` ; `atd` utilise
   `/etc/at/at.{allow,deny}` (`etcdir=/etc/at` dans son `preStart`) et non
   `/etc/at.{allow,deny}`. Écrire les chemins de l'issue n'aurait rien durci.
2. **nixpkgs ouvre délibérément les deux ordonnanceurs.** Vixie-cron, en amont,
   est fermé par défaut : sans `cron.allow` ni `cron.deny`, seul root a droit à
   une crontab. Le module NixOS annule ce défaut dans son `preStart` —
   « *By default, allow all users to create a crontab. This is denoted by the
   existence of an empty cron.deny file.* » Le module `atd` fait de même avec un
   `/etc/at/at.deny` vide. L'écart est donc réel mais hérité, pas une omission
   de STC.
3. **Aucune machine STC n'est concernée aujourd'hui** — `cron.enable=false` et
   `atd.enable=false` sur `local-vm` et `aws-ami` (évalué), rien dans `relics/`,
   `cogitator/` ou `schematics/` ne les active, STC ordonnance par timers systemd.
4. **Mais le module cron s'auto-active.** `services.cron.enable = mkDefault
   (allFiles != [])`, et sa propre doc prévient : « *Many nixos modules set
   systemCronJobs* ». Un consommateur peut donc hériter d'un démon cron ouvert à
   tous les utilisateurs locaux sans l'avoir demandé ni l'avoir vu. C'est le seul
   argument qui justifie du code plutôt qu'un paragraphe de doc : un
   `mkIf config.services.cron.enable` attrape ce cas tout seul, la documentation
   non.

Référentiel : **aucune règle ANSSI-BP-028 ne couvre l'accès aux ordonnanceurs.**
Cet item est CIS-informatif, et STC ne revendique aucune conformité CIS (ligne de
conduite actée en #41). La relique se justifie au mérite — le piège du point 4 —
pas par le référentiel. La matrice ANSSI le dira explicitement.

## Architecture

Nouvelle relique à préoccupation unique sous `relics/nixos/hardening/scheduler.nix`,
sixième membre de la famille `hardening`, câblée dans `cogitator-hardening`. Elle
ne pose **jamais** d'ordonnanceur : son `config` est entièrement gardé par
`mkIf config.services.<x>.enable`, donc elle est inerte sur une machine qui n'en
a pas — ce qui est le cas de tout le parc STC actuel. Frontière DESIGN.md : la
relique configure exactement une chose, la politique d'accès aux ordonnanceurs ;
elle n'installe rien (le seuil de la relique est respecté : le bloc `config`
n'est pas une liste de paquets).

Mécanisme, dicté par le fait que ces fichiers vivent dans de l'état mutable créé
au démarrage du service et non dans `/etc` déclaratif :

| Cible | Mécanisme | Raison |
|-------|-----------|--------|
| `/var/cron/cron.allow` | `systemd.tmpfiles.rules` → `L+` vers un `pkgs.writeText` | `environment.etc` ne peut pas écrire dans `/var`. `L+` remplace à chaque activation, donc le contenu reste déclaratif. tmpfiles passe avant les unités, donc avant le `preStart` de cron. |
| `/etc/at/at.allow` | `environment.etc."at/at.allow"` (`root:atd`, `0640`) | `/etc` déclaratif suffit. Mode et groupe calqués sur le `at.deny` qu'`atd` crée lui-même : le binaire `at` est setuid/setgid `atd` et doit pouvoir le lire. |

Les `*.deny` vides posés par les `preStart` amont ne sont **pas** touchés : cron
comme at évaluent `allow` **d'abord** et ignorent `deny` dès qu'il existe. Rien à
supprimer, donc aucune course avec le `preStart`.

## Global Constraints

- Namespace canonique : `stc.relics.hardening.scheduler.*`. Pas d'alias
  `mkRenamedOptionModule` — la relique est neuve, il n'y a aucun ancien nom à
  faire survivre (Gate 3 sans objet).
- `local-vm` et `aws-ami` doivent continuer à s'évaluer, et à rendre
  `cron.enable=false` / `atd.enable=false` : la relique ne doit activer aucun
  ordonnanceur.
- Proving obligatoire : `cogitator-hardening` gagne une relique, donc
  `provings/hardening.nix` doit prouver l'effet, pas seulement l'évaluation.
- Aucun secret en jeu, donc aucune option en `*File`.
- **Un seul commit.** CLAUDE.md impose la doc dans le même changement qu'une
  modification structurelle, et le proving dans le même changement que la
  revendication. Les étapes ci-dessous sont des unités de travail avec leur
  vérification propre ; elles atterrissent ensemble, comme les trois derniers
  changements de reliques (`5fa14e4`, `109b4f0`, `dbd1f1c`).

## Review Focus

Modes de défaillance qu'aucune commande de vérification d'étape n'exerce, le plus
probable d'abord :

1. **Casse de comportement chez un consommateur qui ne change rien** — s'il a
   cron actif (y compris via l'auto-activation du point 4) *et* des utilisateurs
   non-root qui s'en servent, activer `cogitator-hardening` leur retire le droit
   de crontab. C'est la raison d'être de `allowedUsers`, et ça doit figurer dans
   un bloc `caution` sur la page de la relique, pas seulement dans le CHANGELOG.
2. **Friction `/etc/at` entre `environment.etc` et le `preStart` d'atd** — le
   `install -dm755 -o atd -g atd /etc/at` d'amont s'applique sur un répertoire
   que l'activation `/etc` a déjà peuplé. Le proving ne l'attrape que s'il
   vérifie en plus que l'unité `atd` est bien `active`.
3. **Lien symbolique vers le store refusé par vixie-cron** — si une version
   future vérifiait que `cron.allow` est un fichier régulier ou non lisible par
   tous. L'assert comportemental du proving (un non-root se fait refuser) est ce
   qui le détecterait.
4. **`/var/cron` absent à l'heure de tmpfiles** — une règle `d /var/cron` est
   posée avant la règle `L+` plutôt que de compter sur la création implicite des
   répertoires parents.
5. **Écrasement d'un `cron.allow` entretenu à la main** — `L+` supprime
   l'existant à chaque activation. C'est le comportement voulu (déclaratif), il
   doit être écrit.

## Affected Files

- [ ] `relics/nixos/hardening/scheduler.nix` *(nouveau)*
- [ ] `relics/default.nix`
- [ ] `cogitator/nixos/hardening.nix`
- [ ] `provings/hardening.nix`
- [ ] `docs/src/content/docs/en/relics/hardening.md`
- [ ] `docs/src/content/docs/fr/relics/hardening.md`
- [ ] `docs/src/content/docs/en/relics/index.md`
- [ ] `docs/src/content/docs/fr/relics/index.md`
- [ ] `docs/src/content/docs/en/cogitator/hardening.md`
- [ ] `docs/src/content/docs/fr/cogitator/hardening.md`
- [ ] `docs/src/content/docs/en/reference/anssi-bp-028.md`
- [ ] `docs/src/content/docs/fr/reference/anssi-bp-028.md`

## Atomic Steps

### Step 1 — Implémenter la relique

**Description :** créer `relics/nixos/hardening/scheduler.nix`.

**Interfaces :**
- Consomme : `config.services.cron.enable`, `config.services.atd.enable` (amont).
- Produit : `stc.relics.hardening.scheduler.enable` (bool, `false`),
  `stc.relics.hardening.scheduler.allowedUsers` (`listOf str`, `["root"]`).

**Forme :**

```nix
config = lib.mkIf cfg.enable (lib.mkMerge [
  (lib.mkIf config.services.cron.enable {
    systemd.tmpfiles.rules = [
      "d /var/cron 0755 root root -"
      "L+ /var/cron/cron.allow - - - - ${allowFile}"
    ];
  })
  (lib.mkIf config.services.atd.enable {
    environment.etc."at/at.allow" = {
      source = allowFile;
      user = "root";
      group = "atd";
      mode = "0640";
    };
  })
]);
```

avec `allowFile = pkgs.writeText "scheduler-allow" (concatStringsSep "\n" cfg.allowedUsers + "\n")`.
Une assertion refuse `allowedUsers = []` : une liste vide produit un fichier vide,
que cron lit comme « personne, pas même root », ce qui est un verrouillage total
déguisé en faute de frappe.

**Vérification :** `nix flake check --no-write-lock-file`

### Step 2 — Enregistrer et câbler

**Description :** `relics-hardening-scheduler = ./nixos/hardening/scheduler.nix;`
dans `relics/default.nix` ; import + `stc.relics.hardening.scheduler.enable = true;`
dans `cogitator/nixos/hardening.nix` (et la description de son `mkEnableOption`
passe de cinq à six items).

**Interfaces :** consomme les options du Step 1.

**Vérification :**
```bash
nix flake check --no-write-lock-file
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.services.cron.enable --no-write-lock-file  # doit rester false
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.services.atd.enable --no-write-lock-file     # doit rester false
```

### Step 3 — Proving

**Description :** le nœud de `provings/hardening.nix` active `services.cron`,
`services.atd` et un utilisateur normal de test — sans quoi la relique est inerte
et les asserts ne prouveraient rien (même motif que
`strictIpv6RouterAdvertisements`). Un commentaire le dit sur place.

**Asserts, du plus faible au plus fort :**
1. contenu de `/var/cron/cron.allow` et `/etc/at/at.allow` = `root` ;
2. `systemctl is-active atd` → couvre le Review Focus #2 ;
3. **comportement** : un utilisateur non-root se fait refuser `crontab` et `at` ;
4. **comportement** : root garde l'aller-retour complet (`crontab -` puis
   `crontab -l` ; `at now + 1 hour` puis `atrm`).

**Vérification :** `just test`

### Step 4 — Documentation (EN + FR)

**Description :**
- `relics/hardening.md` : nouvelle section « Scheduler Access », tableau
  d'options, bloc `caution` sur la casse de comportement du Review Focus #1, et
  mention explicite que la relique n'active aucun ordonnanceur. Le `description:`
  du frontmatter et la phrase d'intro passent de cinq à six reliques.
- `cogitator/hardening.md` : la liste des reliques activées, et son `description:`.
- `relics/index.md` : l'entrée de la famille hardening (« all five » → six).
- `reference/anssi-bp-028.md` : une note disant qu'aucune règle BP-028 ne couvre
  les ordonnanceurs et que la relique existe au mérite, pour qu'un lecteur ne
  cherche pas la règle correspondante.

**Vérification :**
```bash
just docs-parity
nix develop .#docs --command npm --prefix docs run astro check
```

## Quality Gates

- [ ] `nix flake check --no-write-lock-file`
- [ ] `nix eval` des deux schematics (drvPath) + `cron.enable`/`atd.enable` restés `false`
- [ ] `grep` des références internes obsolètes (filtré) — vide
- [ ] `just docs-parity`
- [ ] `just test`
- [ ] `just ci`
- [ ] Un commit, signé, `Closes #39`
