# Plan 3-A — Refonte des reliques Docker (dette d'archi, côté STC)

> Chantier A du Plan 3 de la feuille de route. Process : [PROCEDURE_PLANS.md](PROCEDURE_PLANS.md).
> Travail atomique, une branche, commits indépendamment vérifiables, doc synchronisée
> dans le même commit.
>
> **Branche :** `feat/docker-relics-3a` (une PR, l'utilisateur merge/push lui-même).

---

## Objectif

Aligner les reliques Docker de STC sur la règle d'archi durable
(voir [[STC Nix module patterns and gotchas]]) : **STC = câblage réutilisable +
primitives, jamais des versions ni un transport figé**. Deux dettes concrètes :

1. Les reliques d'infra (`traefik`, `crowdsec`, `socket-proxy`) portent des
   **défauts d'image épinglés** (`traefik:v3.7.1@sha256…`) ajoutés en round3.
   C'est en contradiction avec la règle « versions chez le consommateur » et le
   drift est **déjà constaté** : STC pinne `v3.7.1`, l'hôte consommateur
   `../nixos` est en `v3.7.6`. → l'option `image` doit être **requise, sans
   défaut**, avec une assertion au message clair.
2. Le relic `notify.nix` **hardcode ntfy comme transport unique** (curl vers
   `baseUrl`/`topic`). Ce n'est pas flexible : le mécanisme de notification n'est
   pas réutilisable tel quel. → transformer le relic en **hook transport-agnostique**
   (le consommateur fournit la commande de notification), ntfy devenant un simple
   exemple de doc — cohérent avec la philosophie `*File` / backend-agnostic de STC.

## Périmètre

**STC uniquement.** La migration du dépôt consommateur `../nixos` (bascule des
hosts sur les reliques + suppression de `modules/nixos/docker-{traefik,crowdsec}`,
`notify-docker`, `lib/docker`) fait l'objet d'un **plan de suivi séparé** (une
branche par dépôt). Ce plan ne touche que le dépôt STC.

## Hors périmètre (décidé)

- Pas de migration du consommateur (plan de suivi).
- Pas de stacks d'apps (immich, mealie…) — restent chez le consommateur.
- `stc.lib.docker` (`_lib.nix`) est déjà le surensemble du `lib/docker`
  consommateur (options `interval/timeout/retries`, `mkNetwork` sans `ExecStop` +
  `escapeShellArg`) : **rien à changer côté STC**, c'est le consommateur qui
  supprimera son doublon (plan de suivi).

---

## État constaté (analyse préalable)

| Relic | Défaut actuel | Cible |
|---|---|---|
| `traefik.nix` | `image` défaut `traefik:v3.7.1@sha256…` | `default = null` + assertion |
| `crowdsec.nix` | `image` défaut `crowdsecurity/crowdsec:v1.7.8@sha256…` | `default = null` + assertion |
| `socket-proxy.nix` | `image` défaut `tecnativa/docker-socket-proxy:0.3.0@sha256…` | `default = null` + assertion |
| `notify.nix` | transport ntfy hardcodé (`ntfy.baseUrl`, `ntfy.topicFile`) | hook `notifyCommand`, ntfy en exemple doc |

**Rayon d'impact interne :** seul le cogitator `cogitator/nixos/docker-server.nix`
active ces reliques (`traefik/socketProxy/crowdsec/notify`) et **ne pose pas
d'image** (il s'appuie sur les défauts). Aucun schematic ne construit
`docker-server` → **aucune éval de schematic ne casse**. L'assertion `image` ne se
déclenche qu'à l'usage réel chez un consommateur — comportement voulu (migration
douce). Le cogitator documente déjà en en-tête les options machine-spécifiques à
fournir ; on y ajoute les `image`.

**Contrainte provings (importante) :** une VM `nixosTest` est **isolée réseau**,
donc `docker pull` est impossible. Un proving Docker ne peut asserter que le
**câblage généré** (unités systemd présentes, unités de création de réseau, flags
`--health-*`, labels, fichier de conf Traefik rendu), **pas** des conteneurs
démarrés/healthy. Le proving pinne une image factice à l'intérieur du test
uniquement pour satisfaire l'assertion — il ne la tire jamais.

---

## Étapes atomiques

### Step 1 — Refonte `notify.nix` en hook transport-agnostique

**Description :** retirer le transport ntfy du relic. Le relic conserve tout le
**câblage réutilisable** (health-watch qui `docker kill` l'unhealthy, `OnFailure`,
`StartLimitBurst`/`RestartSec`, label opt-in, résolution unit/container) mais
délègue la notification à une **commande fournie par le consommateur**.

**Changements d'options :**
- **Conservées :** `enable`, `hostname`, `watchLabel`.
- **Nouvelle :** `notifyCommand` — `lib.types.str` (ou `types.path`), **requise
  uniquement quand `enable = true`**. Exécutée à l'échec, reçoit tout par
  **l'environnement** (pas de positionnels) : `STC_NOTIFY_SERVICE` (nom du service
  en échec) et `STC_NOTIFY_HOSTNAME`. Choix env pour l'extensibilité (on pourra
  ajouter `STC_NOTIFY_STATUS`… sans casser les signatures). STC n'a plus aucune
  connaissance de ntfy ni des secrets : la commande lit ses propres secrets
  (cohérent `*File`/agnostique).
- **Retirées :** `ntfy.baseUrl`, `ntfy.topicFile`. Remplacer leurs
  `mkRenamedOptionModule` par des `lib.mkRemovedOptionModule` avec message de
  migration pointant vers `notifyCommand` (on ne peut pas aliaser une
  suppression ; c'est la bonne primitive pour un retrait guidé).
- Conserver les `mkRenamedOptionModule` de `enable`/`hostname`/`watchLabel`.
- Ajouter une `assertion` : `enable → notifyCommand != ""` avec message clair.

**Script interne :** `stc-notify-failure@` invoque désormais `cfg.notifyCommand`
avec `STC_NOTIFY_SERVICE`/`STC_NOTIFY_HOSTNAME` dans l'environnement (via
`serviceConfig.Environment`), au lieu du `curl` ntfy en dur. Le `healthWatchScript`
est inchangé (transport-indépendant).

**Notify reste opt-in — le cogitator ne le force plus.** Aujourd'hui
`docker-server.nix` câble `stc.relics.docker.notify.enable = true;` en dur : après
la refonte, ça rendrait `notifyCommand` **de fait obligatoire** pour tout
consommateur de `docker-server`. On corrige : le cogitator expose
`stc.cogitator.docker-server.notify.enable` (`mkEnableOption`, **défaut off**) et
câble `stc.relics.docker.notify.enable = cfg.notify.enable`. La stack
Traefik+CrowdSec boote donc **sans `notifyCommand`** ; les notifications sont un
opt-in explicite qui n'exige `notifyCommand` que lorsqu'il est activé. Exposer
aussi `notifyCommand` en passthrough sur le cogitator (ou documenter qu'on le pose
sur `stc.relics.docker.notify.notifyCommand`).

**Doc (même commit) :** mettre à jour la page relic notify EN + FR — retirer la
section ntfy comme mécanisme, documenter `notifyCommand`, et **fournir ntfy comme
exemple** (snippet `notifyCommand = "''${pkgs.curl}/bin/curl … https://ntfy.sh/…"`
lisant un `*File`). Mettre à jour l'en-tête du relic (commentaire) et l'en-tête du
cogitator `docker-server.nix` (la ligne `notify.ntfy.topicFile` → exemple
`notifyCommand`).

**Fichiers :**
- `relics/nixos/docker/notify.nix`
- `cogitator/nixos/docker-server.nix` (option `notify.enable` opt-in + en-tête)
- `docs/src/content/docs/en/relics/docker.md` (+ page notify si distincte)
- `docs/src/content/docs/fr/relics/docker.md`
- `docs/src/content/docs/en/cogitator/docker-server.md` + `fr`

**Vérification :**
```bash
nix flake check --no-write-lock-file
grep -rn "ntfy" relics/ cogitator/ --include="*.nix"   # ne doit plus rien câbler en dur
nix develop .#docs -c npm run astro check
```

**Commit :** `refactor(relics-docker): make notify transport-agnostic (drop hardcoded ntfy)`

---

### Step 2 — Rendre l'`image` requise sur les reliques d'infra

**Description :** sur `traefik`, `crowdsec`, `socket-proxy`, remplacer le défaut
d'image épinglé par `default = null` et ajouter une **assertion** «`image` doit
être défini quand le relic est activé» au message explicite (guide le consommateur
à poser `image = "…"; # renovate` dans SON host). Le reste du câblage (réseaux,
healthcheck, labels, conf) est inchangé.

**Fichiers :**
- `relics/nixos/docker/traefik.nix`
- `relics/nixos/docker/crowdsec.nix`
- `relics/nixos/docker/socket-proxy.nix`
- `cogitator/nixos/docker-server.nix` (en-tête : ajouter les `image` aux options
  machine-spécifiques à fournir)
- `docs/src/content/docs/en/relics/docker.md` + `fr` (option `image` : requise,
  exemple `# renovate`)
- `docs/src/content/docs/en/relics/traefik.md` + `fr` (si l'exemple pose `image`)
- `docs/src/content/docs/en/cogitator/docker-server.md` + `fr`

**Vérification :**
```bash
nix flake check --no-write-lock-file
# aucune éval de schematic ne dépend de docker-server, mais on re-valide les 3 :
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file
grep -rn "sha256:" relics/nixos/docker/   # plus aucun digest pinné en défaut
nix develop .#docs -c npm run astro check
```

**Commit :** `refactor(relics-docker): require explicit image on infra relics (no pinned defaults)`

---

### Step 3 — Proving `docker-server` (câblage, image factice pinnée dans le test)

**Description :** ajouter un proving qui boote une VM avec le cogitator
`docker-server` activé (images factices pinnées **dans le test**) et asserte le
**câblage généré**, dans la limite de l'isolation réseau (pas de `docker pull`) :
- les unités systemd des conteneurs existent (`systemctl cat docker-traefik.service`
  etc. — le fichier d'unité existe même si le service ne démarre pas) ;
- les unités oneshot de création de réseau existent (socket-proxy) ;
- les flags `--health-*` et les labels attendus sont présents dans les unités ;
- le `notifyCommand` est bien câblé sur `OnFailure` ;
- le fichier de conf dynamique Traefik est matérialisé.

**Ne pas** attendre de conteneur `healthy` (impossible sans réseau) — le documenter
en tête du fichier, comme la limite `fileSystems` du proving hardening
(voir [[STC Nix module patterns and gotchas]]).

> **Décision d'exécution :** si le câblage assertable sans `docker pull` s'avère
> trop maigre pour justifier un proving VM, replier ce step en **assertion statique**
> sur `config` (`nix eval` sur les unités générées) ou le **différer** en step de
> suivi non bloquant. À trancher au moment de coder, après le Step 2.

**Fichiers :**
- `provings/docker-server.nix`
- `provings/default.nix` (enregistrer `docker-server = pkgs.testers.runNixOSTest …`)
- `Justfile` (étendre `test` pour lancer aussi le nouveau proving)
- `docs/src/content/docs/en/provings/*` + `fr` (mentionner le proving docker)

**Vérification :**
```bash
nix build .#legacyPackages.x86_64-linux.provings.docker-server -L --no-write-lock-file
nix flake check --no-write-lock-file   # legacyPackages ignoré → provings hors gate
just test
nix develop .#docs -c npm run astro check
```

**Commit :** `test(provings): add docker-server wiring proving`

---

## Quality Gates (avant livraison)

- [ ] `nix flake check --no-write-lock-file` vert
- [ ] Les 3 schematics évaluent (local-vm / aws-ami / dreadnought)
- [ ] `grep -rn "sha256:" relics/nixos/docker/` → vide (plus de digest en défaut)
- [ ] `grep -rn "ntfy" relics/ cogitator/ --include="*.nix"` → plus aucun câblage
      ntfy en dur (ntfy uniquement en exemple de doc)
- [ ] `just test` lance les provings (hardening + docker-server) au vert
- [ ] `just ci` inchangé (provings hors gate)
- [ ] Parité doc EN/FR : `just docs-parity` (ou `npm run astro check`)
- [ ] Aucune référence de namespace périmée (Gate 3 de PROCEDURE_PLANS)
- [ ] Chaque commit est atomique et indépendamment vérifiable

## Ordre de livraison

Step 1 (notify) → Step 2 (image requise) → Step 3 (proving). Steps 1 et 2 sont
indépendants ; le Step 3 s'appuie sur les deux (le proving pinne les images et
câble un `notifyCommand` de test).

## Notes de reprise à froid

- **Décisions actées (2026-07-12) :** notify → **hook transport-agnostique**,
  passage par **vars d'env** (`STC_NOTIFY_SERVICE`/`STC_NOTIFY_HOSTNAME`), ntfy en
  exemple ; notify **reste opt-in** — `docker-server` ne force plus `notify.enable`
  (nouvelle option `stc.cogitator.docker-server.notify.enable`, défaut off) ;
  **périmètre STC uniquement**, migration consommateur en plan de suivi.
- Règle durable : reliques docker = câblage seulement, `image` requis sans défaut,
  pas de versions ni d'apps dans STC — voir [[STC Nix module patterns and gotchas]].
- Workflow git : une branche `feat/docker-relics-3a`, commits atomiques,
  **l'utilisateur merge/push** (`--no-ff`). DESIGN.md/PLAN_*.md restent locaux/non
  commités (gouvernance locale) ; seuls les fichiers Nix/docs se committent.
- Gotcha nixosTest : réseau isolé (pas de pull) **et** `fileSystems` écrasé par le
  qemu-vm — asserter du câblage/unités, pas des conteneurs démarrés.
