# REMEDIATION_PLAN.md — Plan de remédiation suite à l'analyse critique

> Plan dressé selon `PROCEDURE_PLANS.md`. Chaque étape = un commit atomique,
> indépendamment vérifiable, avec sa synchro doc bilingue (EN + FR) dans le
> **même commit** lorsqu'un changement est structurel ou modifie un comportement.
>
> Décisions de cadrage (validées) :
> - **Ampleur :** tout, en 4 vagues priorisées.
> - **Socket Docker (S1) :** nouvelle relic `docker-socket-proxy`.
> - **cogitator-vm (S5) :** `docker` devient opt-in (`default = false`) — breaking, note de migration.
> - **Dashboard Traefik (C4) :** `enableDashboard` → `false` par défaut + doc corrigée.

---

## Légende des références

Les codes (S1, C2, Q3…) renvoient au triage de l'analyse critique :
- `S*` = Sécurité, `C*` = Cohérence, `Q*` = Qualité.

## Quality gates (rappel — à passer à chaque commit)

```bash
nix flake check --no-write-lock-file
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file
just ci   # alejandra + statix + deadnix + flake check
```

---

## Vague P0 — Sécurité critique / chaîne CI cassée

### P0.1 — Native Traefik : ne plus logger les headers sensibles  [S2]

**Problème :** `relics/nixos/traefik.nix:58-61` utilise `headers.defaultMode = "keep"`.
Tous les headers (dont `Authorization`, `Cookie`) sont écrits dans
`/var/lib/traefik/access.log`, lui-même persisté via impermanence (`:75-82`).
Ce Traefik natif sert Vaultwarden (`vaultwarden.nix:76`) → tokens de session en clair.

**Fix :** aligner sur le Traefik Docker — `defaultMode = "drop"` + allowlist des
headers non sensibles (`User-Agent`, `X-Real-Ip`, `X-Forwarded-For`, `X-Forwarded-Proto`).

**Fichiers :**
- `relics/nixos/traefik.nix`
- `docs/src/content/docs/en/relics/traefik.md` + `fr/…`

**Commit :** `fix(relics-traefik): drop sensitive headers from native access log`

---

### P0.2 — CI : remplacer `magic-nix-cache-action@v8` (morte)  [Q1]

**Problème :** `.github/workflows/nix.yml` utilise `DeterminateSystems/magic-nix-cache-action@v8`.
L'API sous-jacente a été coupée le 2025-02-01 ; v8 est au mieux un no-op bruyant.

**Fix :** remplacer par `DeterminateSystems/flakehub-cache-action` (ou retirer
le cache et garder juste `nix-installer-action`). Décision par défaut : retirer
l'action morte, ajouter le cache FlakeHub seulement si un compte est configuré.

**Fichiers :** `.github/workflows/nix.yml`

**Commit :** `chore(ci): replace dead magic-nix-cache-action@v8`

---

### P0.3 — Migrer `nixpkgs-stable` 25.05 (EOL) → 25.11  [S3]

**Problème :** `flake.nix:62` épingle `nixos-25.05`, EOL. Utilisé par les shells
forge (terraform/ansible) → plus de correctifs sécurité.

**Fix :** bumper l'input vers `nixos-25.11`, regénérer le lock, ajuster le
commentaire `forge/shells/ansible.nix:5`. Vérifier que les shells terraform/ansible
évaluent encore (paquets toujours présents en 25.11).

**Fichiers :** `flake.nix`, `flake.lock`, `forge/shells/ansible.nix`, `forge/shells/terraform.nix` (si réf.)

**Vérif supplémentaire :**
```bash
nix develop .#ansible --command true
nix develop .#terraform --command true
```

**Commit :** `chore(flake): migrate nixpkgs-stable nixos-25.05 → 25.11`

---

## Vague P1 — Socket-proxy + bugs latents de cohérence

### P1.1 — Nouvelle relic `relics-docker-socket-proxy`  [S1, étape 1/4]

**Problème :** `docker/traefik.nix:136` monte `/run/docker.sock:…:ro`. Le `:ro`
n'empêche pas les requêtes POST à l'API Docker (création de conteneur privilégié → root hôte).

**Fix :** créer `relics/nixos/docker/socket-proxy.nix` — conteneur
`tecnativa/docker-socket-proxy` sur un réseau interne, socket monté `:ro`,
seuls les endpoints en lecture activés (`CONTAINERS=1`, `NETWORKS=1`, `POST=0`, etc.).
Options sous `stc.relics.docker.socketProxy.*` (`enable`, `image`, allowlist endpoints).

**Fichiers :** `relics/nixos/docker/socket-proxy.nix`

**Commit :** `feat(relics): add relics-docker-socket-proxy module`

---

### P1.2 — Enregistrer la relic  [S1, étape 2/4]

**Fichiers :** `relics/default.nix`

**Commit :** `chore(relics): register relics-docker-socket-proxy in flake outputs`

---

### P1.3 — Router le provider Docker de Traefik via le proxy  [S1, étape 3/4]

**Fix :** dans `docker/traefik.nix`, retirer le bind-mount du socket, ajouter
`endpoint: "tcp://socket-proxy:2375"` au provider docker, raccorder Traefik et le
proxy sur un réseau commun. Activer le socket-proxy quand Traefik est activé
(ou laisser le consommateur l'activer explicitement — à trancher en implémentation).

**Fichiers :** `relics/nixos/docker/traefik.nix`

**Vérif :** ré-évaluer les schématiques utilisant docker-server.

**Commit :** `refactor(relics-docker-traefik): route Docker provider through socket-proxy`

---

### P1.4 — Documentation socket-proxy + page Traefik  [S1, étape 4/4]

**Fichiers :**
- `docs/src/content/docs/en/relics/docker.md` (+ `fr/`) — nouvelle section socket-proxy
- `docs/src/content/docs/en/relics/index.md` (+ `fr/`) — entrée d'index
- Page Traefik : corriger la mention du socket

**Commit :** `docs(relics): document docker-socket-proxy and update traefik page`

---

### P1.5 — Ordonnancement `docker-network-web` avant Traefik  [C1]

**Problème :** `docker/traefik.nix:193-195` — `wantedBy = [ "traefik.service" ]`
sans `before`/`requiredBy`. Au 1er boot, Traefik peut démarrer avant le réseau.

**Fix :** ajouter `before = [ "traefik.service" ]` (et `requiredBy` pour forcer
le redémarrage couplé) à l'unité `docker-network-web`.

**Fichiers :** `relics/nixos/docker/traefik.nix`

**Commit :** `fix(relics-docker-traefik): order docker-network-web before traefik`

---

### P1.6 — notify.nix : résoudre le vrai nom d'unité systemd  [C2]

**Problème :** `notify.nix:33-35,102` mappe les noms d'attributs de conteneurs
vers des unités du même nom. Marche pour traefik/crowdsec (qui ont `serviceName`),
mais un conteneur tiers labellisé `stc.docker/health-watch` génère
`docker-<name>.service` → les `OnFailure`/`Restart`/timer s'appliquent à une unité inexistante.

**Fix :** dériver le nom d'unité réel = `c.serviceName or "docker-${name}"` pour
chaque conteneur surveillé, et l'utiliser dans `mapAttrs`/`mapAttrs'` et les timers.

**Fichiers :** `relics/nixos/docker/notify.nix`

**Commit :** `fix(relics-docker-notify): resolve real systemd unit name for watched containers`

---

### P1.7 — Persistence conditionnelle + respect de `persistPath`  [C3]

**Problème :**
- `traefik.nix:75` et `vaultwarden.nix:92` écrivent `environment.persistence."/persist"`
  inconditionnellement (éval casse si impermanence non importé) et en dur.
- `impermanence.nix:95` fige le dataset persist à `${poolName}/persist` alors que
  `persistPath` est configurable.

**Fix :**
- Dans traefik/vaultwarden : guarder avec `lib.mkIf config.stc.relics.impermanence.enable`
  et utiliser `config.stc.relics.impermanence.persistPath` au lieu de `/persist` codé en dur.
- Dans impermanence : ajouter une option `persistDataset` (défaut `"persist"`)
  et dériver `device = "${cfg.poolName}/${cfg.persistDataset}"`.

**Fichiers :** `relics/nixos/traefik.nix`, `relics/nixos/vaultwarden.nix`,
`relics/nixos/impermanence.nix`, docs correspondantes (EN+FR).

**Commit :** `fix(relics): make persistence conditional on impermanence and honor persistPath`

---

## Vague P2 — CI & qualité du dépôt

### P2.1 — CI : job fmt/lint aligné sur `just ci`  [Q2]

**Problème :** `nix.yml` ne lance que `nix flake check` ; alejandra/statix/deadnix
ne sont garantis nulle part.

**Fix :** ajouter un job `lint` exécutant `nix develop --command just ci`
(ou les trois outils séparément).

**Fichiers :** `.github/workflows/nix.yml`

**Commit :** `ci(nix): run fmt + lint (alejandra/statix/deadnix) alongside flake check`

---

### P2.2 — CI : blocs `permissions:` et `concurrency:`  [Q2]

**Fix :** ajouter `permissions: { contents: read }` et un bloc `concurrency`
au workflow nix (le token par défaut a trop de droits ; pas de dédup des runs).

**Fichiers :** `.github/workflows/nix.yml`

**Commit :** `ci(nix): add least-privilege permissions and concurrency`

---

### P2.3 — Dédupliquer les inputs transitifs du `flake.lock`  [Q4]

**Problème :** doublons (≈5 home-manager, flake-compat/snowfall-lib en multiple)
faute de `follows` sur gitflow-toolkit / television-ssh / ansible-recap / etc.

**Fix :** ajouter les `inputs.*.follows = "nixpkgs"` (et `home-manager`) pertinents,
regénérer le lock, vérifier la réduction.

**Fichiers :** `flake.nix`, `flake.lock`

**Commit :** `chore(flake): add follows to dedupe transitive inputs`

---

### P2.4 — README.md racine  [Q3]

**Problème :** `README.md` existe en local mais n'est pas commité → GitHub n'affiche rien.

**Fix :** finaliser + committer un README racine : pitch du projet, liens vers la
doc bilingue (Pages), aperçu relics/cogitator/forge/schematics, commandes dev.

**Fichiers :** `README.md`

**Commit :** `docs: add root README`

---

## Vague P3 — Comportements par défaut, nuances, style

### P3.1 — cogitator-vm : Docker opt-in (`default = false`)  [S5]  ⚠️ breaking

**Problème :** `vm.nix:74-77` met l'user dans `docker` (≈root) + `linger`, sans
avertissement ; avec SSH key-only sans mot de passe, sudo est inutilisable.

**Fix :** `docker.enable` → `default = false`. Documenter docker≈root, le
trade-off `linger`, et l'option `security.sudo.wheelNeedsPassword` côté consommateur.
Note de migration (changement de défaut).

**Fichiers :** `cogitator/nixos/vm.nix`, docs cogitator (EN+FR), note migration.

**Commit :** `feat(cogitator-vm): make docker opt-in (default false)`

---

### P3.2 — Dashboard Traefik Docker : `default = false` + doc corrigée  [C4]

**Problème :** `docker/traefik.nix:45-49,112-116` annonce un dashboard sur
`127.0.0.1:8080` jamais publié → inaccessible. Défaut `true`.

**Fix :** `enableDashboard` → `default = false`, corriger la description (préciser
qu'il faut publier le port pour y accéder).

**Fichiers :** `relics/nixos/docker/traefik.nix`, docs (EN+FR).

**Commit :** `fix(relics-docker-traefik): disable dashboard by default and fix description`

---

### P3.3 — Vaultwarden : retirer `WEBSOCKET_ENABLED` déprécié  [S7]

**Problème :** `vaultwarden.nix:65` — déprécié depuis Vaultwarden 1.29 (websockets
servis sur le port principal).

**Fix :** retirer la ligne.

**Fichiers :** `relics/nixos/vaultwarden.nix`, docs si mentionné.

**Commit :** `fix(relics-vaultwarden): remove deprecated WEBSOCKET_ENABLED`

---

### P3.4 — ZFS : sortir `ZED_DEBUG_LOG` de `/tmp` world-readable  [S7]

**Problème :** `zfs.nix:80` — `ZED_DEBUG_LOG = "/tmp/zed.debug.log"` (tmpfs lisible par tous).

**Fix :** déplacer vers `/var/log/zed.debug.log` (ou retirer si non nécessaire).

**Fichiers :** `relics/nixos/zfs.nix`, docs.

**Commit :** `fix(relics-zfs): move ZED debug log out of world-readable /tmp`

---

### P3.5 — Documenter `random.trust_cpu=on`  [S7]

**Problème :** `aws.nix:55` — confiance aveugle en RDRAND, trade-off non documenté.

**Fix :** commentaire explicatif dans le module + note doc.

**Fichiers :** `relics/nixos/aws.nix`, docs.

**Commit :** `docs(relics-aws): document random.trust_cpu trade-off`

---

### P3.6 — ntfy : avertir du défaut public `ntfy.sh`  [S6]

**Problème :** `notify.nix:68` — par défaut tout part vers `ntfy.sh` public ;
hostnames/services en échec fuient, topic devinable = lisible par tous.

**Fix :** enrichir la description de l'option `baseUrl`/`topicFile` avec l'avertissement.

**Fichiers :** `relics/nixos/docker/notify.nix`, docs.

**Commit :** `docs(relics-docker-notify): warn about public ntfy.sh default`

---

### P3.7 — Schématique dreadnought : durcir les avertissements footgun  [S4]

**Problème :** `schematics/dreadnought/flake.nix:66,71,81` — `wheelNeedsPassword=false`,
`allowNoPasswordLogin=true`, `hostId="cafebabe"` livrés par défaut.

**Fix :** commentaires d'avertissement plus visibles (bloc en-tête), rappel
explicite « ne pas déployer tel quel ». (Comportement gardé : c'est un exemple.)

**Fichiers :** `schematics/dreadnought/flake.nix`, doc schématique (EN+FR).

**Commit :** `docs(schematics-dreadnought): strengthen NOPASSWD/hostId warnings`

---

### P3.8 — Unifier ACME challenge + nom de resolver natif/docker  [C5]  ⚠️ délicat

**Problème :** natif = `httpChallenge` + resolver `letsencrypt` ; docker =
`tlsChallenge` + resolver `lets-encrypt`. Incohérent.

**Fix :** choisir un nom canonique. ⚠️ Le nom du resolver est référencé dans les
configs dynamiques consommateurs (`vaultwarden.nix:82` → `letsencrypt`) → un
renommage est potentiellement breaking. **À traiter avec précaution** : aligner
sur `letsencrypt` côté docker, ou documenter l'écart si trop risqué.

**Fichiers :** `relics/nixos/docker/traefik.nix`, docs.

**Commit :** `refactor(relics-docker-traefik): align ACME resolver naming with native`

---

### P3.9 — Documenter le trade-off `flake.lock` par schématique  [C6]

**Fix :** note dans la doc schématiques : lock séparé (`path:../..`) = double source
de vérité assumée, à regénérer après modif du parent.

**Fichiers :** `docs/src/content/docs/en/schematics/index.md` (+ `fr/`).

**Commit :** `docs(schematics): document per-schematic flake.lock trade-off`

---

### P3.10 — ZFS : option kernel LTS au lieu du `latest` forcé  [Q5]  (optionnel)

**Problème :** `zfs.nix:13,55` force le kernel ZFS-compatible le plus récent →
churn au rythme de nixpkgs-unstable sur des machines « production ».

**Fix :** ajouter une option `kernel = "latest" | "lts"` (défaut conservateur à
décider), conserver `latest` comme choix.

**Fichiers :** `relics/nixos/zfs.nix`, docs.

**Commit :** `feat(relics-zfs): add optional LTS kernel selection`

---

### P3.12 — Doc : remplacer les namespaces dépréciés dans les exemples  [dette découverte en P1]

**Problème :** ~7 paires de pages (EN+FR) utilisent encore le namespace **déprécié**
dans leurs exemples au lieu du canonique `stc.relics.*` :
`vaultwarden.md` (`stc.traefik`, `stc.vaultwarden`), `traefik.md` (`stc.traefik`),
`aws.md` (`stc.aws`), `zfs.md` (`stc.zfs`), `impermanence.md` (`stc.impermanence`),
`forge/layouts.md` (`stc.impermanence`), `docker.md` (`stc.docker`).
Note : `stc.docker/health-watch` est un *label* Docker, pas un namespace — à laisser.

**Fix :** remplacer chaque exemple par le namespace canonique. Nos propres docs
doivent enseigner le canonique ; les aliases ne servent qu'aux consommateurs externes.

**Fichiers :** les 7 paires de pages ci-dessus (EN+FR).

**Commit :** `docs: use canonical stc.relics.* namespace in examples`

---

### P3.11 — Formatage global  [C5]

**Fix :** `nix develop --command just fmt` sur tout le dépôt pour homogénéiser
(ex. `cogitator/default.nix` compact vs style aéré ailleurs).

**Commit :** `style: apply alejandra formatting repo-wide`

---

## Ordre d'exécution recommandé

1. **P0** (3 commits) — risque sécurité direct + CI réparée d'abord.
2. **P1** (7 commits) — socket-proxy + bugs latents.
3. **P2** (4 commits) — CI/qualité.
4. **P3** (11 commits) — défauts, nuances, style. P3.8 et P3.10 à arbitrer.

Total : ~25 commits atomiques. Chaque commit passe les quality gates seul.
