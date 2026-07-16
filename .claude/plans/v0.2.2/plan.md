# Remediation Plan — Round 3 (sécurité/stabilisation)

> Suite au retour de revue sur le commit `541a520` (merge PR #10).
> Process : [PROCEDURE_PLANS.md](PROCEDURE_PLANS.md). Travail atomique, une branche,
> commits indépendamment vérifiables, doc synchronisée dans le même commit.

**Branche :** `remediation/round3-bugfixes` (une PR, à l'image de round2).

**Principe directeur :** ne pas casser ce qui fonctionne. Les changements de
comportement runtime sont exposés en **options opt-in dont le défaut préserve le
comportement actuel** (décision utilisateur). Chaque commit est validé par
`nix flake check` + eval des schematics concernés avant d'être figé.

---

## Évaluation critique du retour

| # | Point | Verdict | Action |
|---|-------|---------|--------|
| 1 | `filesystem.nix` `or` au lieu de `\|\|` | **Vrai bug confirmé** | Corriger |
| 2 | `aws.nix` device Xen `xvdap3` | **Vrai bug confirmé** | Dériver le suffixe |
| 3 | Sarcophagus : commentaires disko/EFI contradictoires | **Confirmé** (kvm header déjà fait en `07d59db`) | Corriger commentaires aws + bloc disko des 2 |
| 4 | Asymétrie fileSystems kvm/aws | **Confirmé, pas un bug** | Harmoniser prudemment (eval) ou documenter si risque |
| 5 | Pinning traefik/crowdsec | Décision politique → **pin par digest** | Résoudre digests, épingler |
| 6 | certResolver conteneur ≠ natif | Changement comportement → **option opt-in défaut off** | Ajouter option |
| 7a | ssh.nix « idle sessions » | Confirmé (nuance ClientAlive) | Doc |
| 7b | dashboard tunnel SSH | Confirmé | Doc |
| 7c | flake header `-drive file=result` | Confirmé | Doc |
| 7d | zfs.nix `\|\| true` | Confirmé (pattern PR #10) | Retirer prudemment |
| S1 | vm.nix `linger` hardcodé | Confirmé | Option opt-in, défaut `true` |
| S2 | Kex PQ vs version OpenSSH | Confirmé (risque lockout) | Assertion version |
| S3 | rp_filter strict | Judgment | Option, défaut strict (1) |
| S4 | yama.ptrace_scope absent | Gap | Ajouter (hardening) |
| S5 | docker-notify : conteneur unhealthy meurt | Confirmé | Doc |

---

## Étapes atomiques

Ordre choisi : vrais bugs d'abord, puis incohérences, puis doc, puis sécurité, puis pinning.

### Commit 1 — `fix(hardening-filesystem): fire hidepid warning on Plasma (|| not or)`
- **Fichier :** `relics/nixos/hardening/filesystem.nix:94`
- `config.services.xserver.enable or … or false` → `||`. `or` est la sélection
  d'attribut avec défaut ; comme `services.xserver.enable` existe toujours,
  l'expression se réduit à `xserver.enable` (que `plasma6` met à `false`).
- **Doc :** aucune (logique interne).
- **Vérif :** `nix flake check` ; `nix eval ...local-vm...qcow2.drvPath`.

### Commit 2 — `fix(relics-aws): derive partition separator for Xen devices`
- **Fichier :** `relics/nixos/aws.nix`
- Ajouter `partSep = if (builtins.match ".*[0-9]" cfg.ebsDisk) != null then "p" else "";`
  et l'utiliser dans `zpool online -e … /dev/${cfg.ebsDisk}${partSep}${toString cfg.ebsPartition}`.
  `nvme0n1`→`nvme0n1p3`, `xvda`→`xvda3`.
- **Doc :** `docs/{en,fr}/relics/aws.md` si le device y est décrit.
- **Vérif :** `nix eval ...aws-ami...awsImage.drvPath`.

### Commit 3 — `docs(cogitator-sarcophagus): clarify disko block is descriptive, fix partition comments`
- **Fichiers :** `cogitator/nixos/sarcophagus-aws.nix` (en-tête « 1G EFI » → BIOS/GRUB),
  `sarcophagus-{aws,kvm}.nix` (commentaires « Partition 1/2 » → noter que le builder
  `make-single-disk-zfs-image.nix` crée bios_grub(1)+ESP(2)+ZFS(3), et que le bloc
  `disko` sert uniquement à générer `fileSystems`, pas à partitionner l'image).
- **Doc :** `docs/{en,fr}/cogitator/sarcophagus-{aws,kvm}.md` si le layout y est décrit.
- **Vérif :** eval des 2 schematics (kvm via local-vm, aws via aws-ami).
- **Note :** commentaires uniquement, zéro changement de comportement.

### Commit 4 — `refactor(cogitator-sarcophagus-kvm): align fileSystems declaration with aws` *(conditionnel)*
- **Fichier :** `cogitator/nixos/sarcophagus-kvm.nix`
- Objectif : supprimer l'asymétrie (aws déclare `/` et `/nix` explicitement, kvm s'appuie
  sur disko). **À investiguer d'abord** : vérifier si le module disko émet déjà
  `config.fileSystems` ici (conflit potentiel). Si l'harmonisation casse l'eval,
  **basculer en doc-only** : documenter pourquoi les deux divergent.
- **Vérif :** `nix eval ...local-vm...qcow2.drvPath` doit passer inchangé.
- **Garde-fou :** si eval échoue → revert vers commentaire explicatif uniquement.

### Commit 5 — `refactor(relics-zfs): guard autoSnapshot on dataset existence instead of || true`
- **Fichier :** `relics/nixos/zfs.nix:130-133`
- Ne PAS simplement retirer `|| true` : `zfs set` est idempotent (re-run au boot
  suivant = no-op, exit 0), donc pas de souci « déjà au max »/boots futurs ici.
  Le seul échec que `|| true` masquait est un dataset absent. On remplace par une
  **garde sur l'existence** (`zfs list -H -o name <ds>`) : skip propre si absent,
  échec bruyant si `zfs set` plante sur un dataset existant (vrai problème).
  Helper `setSnapshot = ds: val: ''if ${zfs} list … then ${zfs} set … else echo skip''`.
- **Doc :** `docs/{en,fr}/relics/zfs.md` (comportement autoSnapshot inchangé côté option).
- **Vérif :** `nix flake check` ; eval local-vm.
- **Hors scope :** la gestion d'erreurs de `growpart`/`zpool online` dans `aws.nix`
  est déjà correcte (`f14d5dd` : rc=1 NOCHANGE toléré, ≥2 échoue) — non touchée.

### Commit 6 — `docs: fix ssh idle-session, dashboard tunnel, local-vm drive path`
- **Fichiers :**
  - `relics/nixos/hardening/ssh.nix:43` : reformuler — ClientAlive déconnecte les
    clients **injoignables**, pas les sessions inactives.
  - `relics/nixos/docker/traefik.nix:141-145` : le loopback `127.0.0.1:8080` est
    celui du **conteneur** ; un tunnel SSH vers l'hôte n'y arrive pas sans publier le port.
  - `schematics/local-vm/flake.nix:12` : `-drive file=result` →
    `-drive file=./result/nixos.root.qcow2,if=virtio,format=qcow2` (aligné sur le Justfile).
- **Doc :** pages relics/schematics correspondantes si concernées.
- **Vérif :** commentaires/doc only.

### Commit 7 — `feat(cogitator-vm): make user lingering opt-in (default true)`
- **Fichier :** `cogitator/nixos/vm.nix`
- Ajouter `linger = lib.mkOption { type = bool; default = true; description = ...; }`
  (expliquer que le lingering laisse tourner des services user sans session).
  Utiliser `linger = cfg.linger;`.
- **Doc :** `docs/{en,fr}/cogitator/vm.md`.
- **Vérif :** eval local-vm (utilise cogitator-vm).

### Commit 8 — `feat(hardening-network): make reverse-path filter mode configurable`
- **Fichier :** `relics/nixos/hardening/network.nix`
- Option `strictReversePathFilter` (bool, défaut `true` → `rp_filter=1` ; `false` → `2` loose).
  Documenter le cas WireGuard/multi-homed.
- **Doc :** `docs/{en,fr}/relics/hardening.md`.
- **Vérif :** `nix flake check`.

### Commit 9 — `feat(hardening-kernel): restrict ptrace via yama.ptrace_scope`
- **Fichier :** `relics/nixos/hardening/kernel.nix`
- Ajouter `"kernel.yama.ptrace_scope" = 1;` (cohérent avec perf_event_paranoid /
  unprivileged_bpf_disabled). Commenter l'impact (gdb attach limité aux enfants).
- **Doc :** `docs/{en,fr}/relics/hardening.md`.
- **Vérif :** `nix flake check`.

### Commit 10 — `feat(hardening-ssh): assert OpenSSH supports post-quantum kex`
- **Fichier :** `relics/nixos/hardening/ssh.nix`
- `assertions = [{ assertion = lib.versionAtLeast config.services.openssh.package.version "9.9";
  message = "...mlkem768x25519-sha256 nécessite OpenSSH ≥ 9.9..."; }];`
  Évite le lockout silencieux sur un nixpkgs ancien (via `follows`).
- **Doc :** `docs/{en,fr}/relics/hardening.md` (mention version minimale).
- **Vérif :** `nix flake check`.

### Commit 11 — `chore(relics-docker): pin traefik and crowdsec images by digest`
- **Fichiers :** `relics/nixos/docker/traefik.nix`, `relics/nixos/docker/crowdsec.nix`
- Résoudre les digests (`skopeo inspect` via nix, ou `docker manifest inspect`) et
  passer à `image = "traefik:v3.7.1@sha256:..."` / `crowdsec:v1.7.8@sha256:..."`,
  tag conservé pour la lisibilité (même commentaire que socket-proxy).
- **Doc :** `docs/{en,fr}/relics/docker.md` si les images y figurent.
- **Vérif :** `nix flake check` ; eval dreadnought (docker-server).
- **Prérequis :** accès registre pour résoudre les digests.

### Commit 12 — `docs(docker-notify): note that a persistently-unhealthy container stops`
- **Fichier :** `relics/nixos/docker/notify.nix` (commentaire d'en-tête)
- Documenter : un conteneur durablement `unhealthy` est `docker kill` toutes les 30 s,
  atteint `StartLimitBurst=3` en ~90 s et reste arrêté — seul signal : la notif ntfy.
- **Doc :** `docs/{en,fr}/relics/docker.md`.
- **Vérif :** doc only.

---

## Quality Gates (avant PR)

- [ ] `nix flake check --no-write-lock-file`
- [ ] `nix eval ./schematics/local-vm#...qcow2.drvPath --no-write-lock-file`
- [ ] `nix eval ./schematics/aws-ami#...awsImage.drvPath --no-write-lock-file`
- [ ] `nix eval ./schematics/dreadnought#...toplevel.drvPath --no-write-lock-file`
- [ ] `just ci` (alejandra + statix + deadnix)
- [ ] Parité doc en/fr (script CI existant)
- [ ] Chaque commit vérifié indépendamment

---

**Statut :** Exécuté le 2026-06-07 sur la branche `remediation/round3-bugfixes`
(12 commits atomiques). Gates passés : `just ci` (alejandra + statix + deadnix +
`nix flake check` + parité docs en/fr), eval des 3 schematics (local-vm qcow2,
aws-ami awsImage, dreadnought toplevel). En attente de push/PR.
