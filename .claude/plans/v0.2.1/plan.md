# REMEDIATION_PLAN_v2.md — Round 2 (analyse post-remédiation)

> Plan dressé selon `PROCEDURE_PLANS.md`. Chaque étape = un commit atomique,
> indépendamment vérifiable, avec sa synchro doc bilingue (EN + FR) dans le
> **même commit** dès qu'un changement est structurel ou modifie un comportement.
>
> Ce plan fait suite à une **seconde** analyse critique, menée sur le dépôt
> **déjà remédié** par `REMEDIATION_PLAN.md` (vague P0–P3, mergée). Plusieurs
> findings approfondissent des points que la vague 1 avait seulement effleurés
> (ex. l'ordering `docker-network-web` ajouté en P1.5 ne suffit pas).
>
> Périmètre validé : **tout** (bugs + cohérence + polish).

---

## Deux décisions d'architecture — VALIDÉES

> **Décision A = A1** (réseau `web` minimal, pattern socket-proxy) — validée.
> **Décision B = B1** (garder natif + Docker, documenter l'asymétrie) — validée.


### Décision A — réseau Docker `web` partagé

**Problème (finding #1).** Le réseau `web` est créé par `docker/traefik.nix`
(`docker-network-web`, ordering `before`/`requiredBy` sur `traefik.service`
uniquement, l.229-230). `crowdsec` joint `networks = ["web"]` (crowdsec.nix:74)
**sans aucun ordering** et démarre *avant* Traefik (via `Requires=crowdsec`),
donc peut courir devant la création du réseau au 1er boot. Pire : crowdsec activé
**seul**, le réseau `web` n'est créé par personne.

**Options :**
- **A1 (recommandé, minimal, conforme au pattern socket-proxy).** Traefik reste
  propriétaire de `web` mais ordonne le réseau `before`/`requiredBy` sur *tous*
  les consommateurs connus (traefik **et** crowdsec, via le guard `crowdsecEnabled`
  déjà présent). crowdsec émet l'unité `docker-network-web` lui-même **uniquement
  quand Traefik est absent** (guard `!traefikCfg.enable`, réutilise
  `dockerLib.mkNetwork`) et ordonne son conteneur après. Aucun nouveau relic.
- **A2 (plus pur DESCRIPTION single-responsibility, plus lourd).** Extraire un
  relic dédié `relics-docker-network-web` qui possède `web` + l'ordering ; traefik
  et crowdsec référencent l'unité par son nom (pas d'import). Coût : nouveau relic
  à documenter + charge consommateur (l'activer, ou un cogitator qui compose).

→ **Recommandation : A1.** Présente le moins de surface, colle au précédent
`socket-proxy`, et résout race + cas standalone.

### Décision B — deux Traefik (natif vs Docker)

**Constat (finding « deux résolveurs ACME »).** Le dépôt expose **deux** relics
Traefik : `relics/nixos/traefik.nix` (natif `services.traefik`, httpChallenge) et
`relics/nixos/docker/traefik.nix` (conteneur, tlsChallenge). Vaultwarden câble le
**natif**. L'asymétrie ACME est un symptôme : ce sont deux déploiements distincts.

**Options :**
- **B1 (recommandé).** Les deux modes sont supportés et assumés. Action :
  documenter explicitement le choix natif/Docker, aligner ce qui peut l'être
  sans casser (nom de resolver déjà unifié sur `letsencrypt` en vague 1 ;
  documenter la différence de challenge http vs tls et *pourquoi*). Pas de
  consolidation.
- **B2.** Considérer l'un des deux comme legacy et consolider. Refonte lourde,
  breaking, hors périmètre d'un round de correctifs.

→ **Recommandation : B1.** Le bug fonctionnel (Vaultwarden DOMAIN) est de toute
façon indépendant de cette décision.

---

## Quality gates (à passer à chaque commit)

```bash
nix flake check --no-write-lock-file
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file
just ci
```

---

## Vague R0 — bugs fonctionnels & crypto (faible risque, fort impact, sans décision d'archi)

### R0.1 — Vaultwarden : définir `DOMAIN`  [bug #3]

**Problème :** `vaultwarden.nix` ne pousse jamais `DOMAIN` dans
`services.vaultwarden.config`. Sans lui : WebAuthn/passkeys, pièces jointes et
liens d'invitation cassés ou incorrects derrière un proxy (doc Vaultwarden).

**Fix :** `DOMAIN = "https://${cfg.hostname}";` dans le bloc `config` (le hostname
est déjà sous la main).

**Fichiers :** `relics/nixos/vaultwarden.nix`, docs vaultwarden (EN+FR).

**Commit :** `fix(relics-vaultwarden): set DOMAIN for proxy/WebAuthn correctness`

---

### R0.2 — SSH : hybrides PQ + passage aux réglages typés  [bug #4]

**Problème :** `hardening/ssh.nix:55-59` pinne `KexAlgorithms` via `extraConfig`
(contourne la validation du module) et **exclut** les échanges hybrides
post-quantiques (`sntrup761x25519-sha512@openssh.com`, `mlkem768x25519-sha256`).
Le « hardening » retire donc une protection que la default OpenSSH récente offre.

**Fix :** passer `Ciphers`/`MACs`/`KexAlgorithms` en `services.openssh.settings`
typés ; mettre les hybrides PQ **en tête** de `KexAlgorithms`. Vérifier la version
OpenSSH du pin nixpkgs pour `mlkem768x25519` (≥ 9.9) — gater si nécessaire.

**Fichiers :** `relics/nixos/hardening/ssh.nix`, docs hardening (EN+FR).

**Vérif supplémentaire :**
```bash
nix eval --raw nixpkgs#openssh.version   # confirmer ≥ 9.9 pour mlkem
```

**Commit :** `fix(relics-hardening-ssh): add PQ hybrid KEX, move to typed settings`

---

### R0.3 — health-watch : tester la VALEUR du label, pas sa présence  [bug #6]

**Problème :** `notify.nix:39` filtre `(c.labels or {}) ? ${cfg.watchLabel}` —
présence seule. Un conteneur `"stc.docker/health-watch" = "false"` est surveillé.

**Fix :** `(c.labels.${cfg.watchLabel} or "false") == "true"`.

**Fichiers :** `relics/nixos/docker/notify.nix`, doc notify si l'exemple le mentionne.

**Commit :** `fix(relics-docker-notify): match health-watch label value, not presence`

---

### R0.4 — `mkNetwork` : retirer le `ExecStop` destructeur  [bug #5]

**Problème :** `_lib.nix:26` — `ExecStop = docker network rm -f ${name}`. Un restart
de l'unité détruit le réseau sous les conteneurs attachés. `${name}` interpolé sans
`escapeShellArg` (cosmétique, valeur contrôlée).

**Fix :** supprimer `ExecStop` (réseau idempotent à la création, inutile de le
démonter). Optionnel : `lib.escapeShellArg name` dans le script.

**Fichiers :** `relics/nixos/docker/_lib.nix`.

**Vérif :** `socket-proxy` et `docker-network-web` évaluent encore.

**Commit :** `fix(lib-docker): drop destructive ExecStop from mkNetwork`

---

## Vague R1 — disponibilité & ordonnancement (Décision A + couplage WAF/proxy)

### R1.1 — Réseau `web` : ordering complet + cas standalone  [bug #1, Décision A]

**Fix (selon A1 retenu) :**
- `docker/traefik.nix` : `docker-network-web` ordonne `before`/`requiredBy` sur
  traefik **et** crowdsec (quand `crowdsecEnabled`).
- `docker/crowdsec.nix` : émettre `docker-network-web` (via `dockerLib.mkNetwork`)
  **uniquement si Traefik absent**, et ordonner `crowdsec.service` après l'unité.

**Fichiers :** `relics/nixos/docker/traefik.nix`, `relics/nixos/docker/crowdsec.nix`,
docs docker (EN+FR).

**Commit :** `fix(relics-docker): make web network reliable before all consumers`

---

### R1.2 — Traefik : `Wants` au lieu de `Requires` sur crowdsec  [bug #2]

**Problème :** `docker/traefik.nix:216-221` — `Requires=crowdsec.service`. Couplé
au `docker kill` du health-watch (notify.nix:33), un crowdsec qui flanche peut
faire tomber le reverse proxy (et tout ce qu'il sert).

**Fix :** `Wants` + `After` (ordre préservé, panne non propagée). Un WAF/IDS en
panne ne doit pas faire tomber le proxy.

**Fichiers :** `relics/nixos/docker/traefik.nix`, doc docker (EN+FR — préciser le
trade-off disponibilité vs protection).

**Commit :** `fix(relics-docker-traefik): depend on crowdsec via Wants, not Requires`

---

### R1.3 — Logrotate Traefik : réouverture du log via USR1  [incohérence I3]

**Problème :** `docker/traefik.nix:196-205` — `copytruncate` sur le log que
crowdsec taile. Fenêtre de perte de lignes à la rotation → attaques potentiellement
non vues par l'IDS.

**Fix :** retirer `copytruncate`, ajouter un `postrotate`
`docker kill -s USR1 traefik` (Traefik réouvre ses logs sur USR1).

**Fichiers :** `relics/nixos/docker/traefik.nix`, doc docker (EN+FR).

**Commit :** `fix(relics-docker-traefik): reopen log via USR1 instead of copytruncate`

---

## Vague R2 — cohérence, terminologie, vérité de la doc (Décision B)

### R2.1 — Documenter le split natif/Docker + asymétrie ACME  [incohérence I1, Décision B]

**Fix (selon B1) :** note dans la doc Traefik expliquant les deux déploiements
(natif `services.traefik` httpChallenge vs Docker tlsChallenge) et *pourquoi*.
Commentaire d'en-tête dans les deux modules pour pointer l'un vers l'autre.

**Fichiers :** `relics/nixos/traefik.nix`, `relics/nixos/docker/traefik.nix`,
docs traefik (EN+FR).

**Commit :** `docs(relics-traefik): explain native vs Docker deployment & ACME challenge`

---

### R2.2 — Terminologie : CrowdSec = IDS/IPS comportemental, pas WAF  [incohérence I5]

**Problème :** « CrowdSec WAF » (crowdsec.nix:3,26 + README/docs). En mode lecture
de logs, c'est un IDS/IPS comportemental — pas un WAF (composant AppSec non configuré).

**Fix :** remplacer « WAF » par « IDS/IPS » dans le commentaire d'en-tête, la
`mkEnableOption`, le README et les docs.

**Fichiers :** `relics/nixos/docker/crowdsec.nix`, `README.md`, docs (EN+FR).

**Commit :** `docs(relics-docker-crowdsec): describe CrowdSec as IDS/IPS, not WAF`

---

### R2.3 — `just ci` aligné avec la CI réelle  [incohérence I2]

**Problème :** `Justfile` lance `nix flake check --show-trace` ; le workflow lance
`--no-write-lock-file` sans `--show-trace`. Drift qui divergera.

**Fix :** harmoniser les flags (mêmes options des deux côtés).

**Fichiers :** `Justfile`, `.github/workflows/nix.yml`.

**Commit :** `chore(ci): align just ci flake-check flags with CI workflow`

---

### R2.4 — `sarcophagus-kvm.nix` : corriger l'en-tête contradictoire  [incohérence I4]

**Problème :** l'en-tête dit « 1G EFI » alors que le corps explique trois lignes
plus bas que c'est du BIOS/GRUB (exigence de `make-single-disk-zfs-image.nix`),
avec une partition `EF00` qui n'est pas un vrai ESP.

**Fix :** corriger le commentaire d'en-tête pour refléter le BIOS/GRUB réel.

**Fichiers :** `cogitator/nixos/sarcophagus-kvm.nix`.

**Commit :** `docs(cogitator-sarcophagus-kvm): fix contradictory EFI/BIOS header comment`

---

## Vague R3 — défauts robustes & pédagogie des exemples

### R3.1 — `growpart` : oneshot `ConditionFirstBoot` au lieu d'activation script  [détail D4]

**Problème :** `aws.nix` lance `growpart` en activation script à chaque
`nixos-rebuild switch`, avec `|| true` qui avale aussi les vraies erreurs.

**Fix :** service oneshot avec `ConditionFirstBoot=yes` (ou test du code retour :
1 = no-op vs ≠1 = vraie erreur).

**Fichiers :** `relics/nixos/aws.nix`, docs aws (EN+FR).

**Commit :** `fix(relics-aws): run growpart as first-boot oneshot, not every rebuild`

---

### R3.2 — Schématique local-vm : pédagogie hostId / mot de passe  [détail D2]

**Problème :** `networking.hostId = "deadc0de"` livré comme valeur réelle,
`initialPassword = "changeme"` avec `mutableUsers = false` → mot de passe jamais
changeable, reste `changeme`.

**Fix :** `lib.warn` explicite (ou `hashedPassword` requis / commentaire fort)
pour signaler que ce sont des placeholders à remplacer.

**Fichiers :** `schematics/local-vm/flake.nix`, doc schématique (EN+FR).

**Commit :** `docs(schematics-local-vm): warn on placeholder hostId/password`

---

### R3.3 — hidepid + desktop : avertir/tester la composition  [détail D3]

**Problème :** `hidepid=2` gère systemd-logind via le groupe proc, mais casse
polkit, agents D-Bus utilisateur et exporters Prometheus. `cogitator-plasma` +
`cogitator-hardening` sont censés se composer.

**Fix :** avertissement (comme pour gaming) ou assertion documentée sur la
combinaison hardening + desktop.

**Fichiers :** `relics/nixos/hardening/*.nix` (proc/hidepid), docs (EN+FR).

**Commit :** `docs(relics-hardening): warn about hidepid breaking desktop/polkit/exporters`

---

### R3.4 — Pinner le socket-proxy par digest  [détail D1]

**Problème :** images pinnées par tag mutable. Le socket-proxy détient la socket
Docker brute → enjeu le plus fort.

**Fix :** pinner au moins `tecnativa/docker-socket-proxy` par `image@sha256:…`
(décision : digest sur le socket-proxy ; pour les autres, à arbitrer en impl).

**Fichiers :** `relics/nixos/docker/socket-proxy.nix`, doc docker (EN+FR).

**Commit :** `chore(relics-docker-socket-proxy): pin image by digest`

---

## Vague R4 — CI & maintenabilité long terme

### R4.1 — CI : pinner les actions par SHA  [détail D5]

**Problème :** actions pinnées par tag (`@v4`, `@v16`) — incohérent avec la
philosophie lockfile du dépôt.

**Fix :** pinner chaque action par SHA commit (+ commentaire de version).

**Fichiers :** `.github/workflows/*.yml`.

**Commit :** `ci: pin GitHub Actions by commit SHA`

---

### R4.2 — CI : check de désynchronisation en/fr  [détail D6]

**Problème :** 40+ fichiers doc miroir à la main, aucune détection de désync.
Point qui pourrira le plus vite.

**Fix :** step CI comparant les arborescences `docs/.../en` et `docs/.../fr`
(mêmes chemins relatifs présents des deux côtés).

**Fichiers :** `.github/workflows/*.yml` (+ éventuel script dans `forge/` ou racine).

**Commit :** `ci(docs): detect en/fr documentation tree desync`

---

## État d'avancement

Toutes les vagues R0–R4 sont **implémentées** dans l'arbre de travail (code + docs
EN/FR), `nix flake check` vert après chaque vague. Commits non encore créés
(branche à faire depuis `main` au feu vert).

- R0.1 Vaultwarden DOMAIN ✓ · R0.2 SSH PQ+typed ✓ · R0.3 label valeur ✓ · R0.4 ExecStop ✓
- R1.1 réseau web fiable + cas standalone ✓ · R1.2 Wants ✓ · R1.3 logrotate USR1 ✓
- R2.1 doc natif/Docker ✓ · R2.2 IDS/IPS ✓ · R2.3 flags just/CI ✓ · R2.4 en-tête sarcophagus ✓
- R3.1 growpart oneshot ✓ · R3.2 warnings local-vm ✓ · R3.3 hidepid+desktop ✓ · R3.4 digest socket-proxy ✓
- R4.1 actions par SHA ✓ · R4.2 check parité en/fr (script + Justfile + CI) ✓

Bonus découvert et corrigé : `crowdsec.nix` forçait `traefik.enable` sans guard
d'existence → crowdsec seul cassait à l'éval ; corrigé par le guard `options ? traefik`.

---

## Ordre d'exécution recommandé

1. **R0** (4 commits) — bugs fonctionnels/crypto, sans dépendance d'archi.
2. **R1** (3 commits) — disponibilité/ordering (après validation Décision A).
3. **R2** (4 commits) — cohérence/terminologie/doc (après validation Décision B).
4. **R3** (4 commits) — défauts robustes & pédagogie.
5. **R4** (2 commits) — CI/maintenabilité.

Total : ~17 commits atomiques. Chaque commit passe les quality gates seul.

**Bloquants avant code :** valider Décision A (A1 vs A2) et Décision B (B1 vs B2).
