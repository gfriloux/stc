# Plan 3-B — Absorption du durcissement fait-main (côté STC)

> Chantier B du Plan 3 de la feuille de route. Process : [PROCEDURE_PLANS.md](PROCEDURE_PLANS.md).
> Travail atomique, une branche, commits indépendamment vérifiables, doc synchronisée
> dans le même commit.
>
> **Branche :** `feat/hardening-3b` (une PR, l'utilisateur merge/push lui-même).

---

## Objectif

Upstreamer dans les reliques hardening STC ce que le consommateur `../nixos`
(host `exampleHost`) fait **à la main** et que STC n'a pas encore. But durable :
`stc.cogitator.hardening` reste le **socle universel** et devient un **surensemble**
de ce que fait exampleHost, pour que la future migration du consommateur (plan de
suivi séparé) ne perde **aucun** réglage.

Trois dettes concrètes constatées dans `exampleHost` :

1. **`net.core.bpf_jit_harden = 2`** — durcit le JIT eBPF. La matrice ANSSI de STC
   le liste déjà comme réglage **R12 non couvert** (`⚪`). → l'absorber dans le
   relic `network.nix`, il passe `✅`.
2. **`blacklistedKernelModules`** — firewire (vecteur DMA) + protocoles réseau
   rares/legacy (dccp/sctp/rds/tipc, vecteurs CVE fréquents). STC n'a **rien**. →
   **nouveau relic** `hardening/modules.nix`, tiré par le socle `cogitator.hardening`.
3. **SSH `PerSourcePenalties`** — rate-limiting anti-bruteforce. Le relic `ssh.nix`
   ne le pose pas. → l'absorber pour parité (OpenSSH ≥ 9.8, déjà couvert par
   l'assertion ≥ 9.9 du relic).

Bonus décidé (sysctls R12 sûrs, au-delà d'exampleHost) : `accept_source_route=0`
(v4+v6) et `tcp_rfc1337=1`, sans impact runtime → inconditionnels. Durcissement
`arp_*` derrière une option **désactivée par défaut** (risque multi-homed/docker).

## Périmètre

**STC uniquement.** La migration d'`exampleHost` (bascule sur les reliques +
suppression de son bloc `boot.nix` hardening et de ses settings openssh) fait
l'objet d'un **plan de suivi séparé**. Ce plan ne touche que le dépôt STC.

## Hors périmètre (décidé)

- Pas de migration du consommateur (plan de suivi).
- `fs.file-max` (tuning capacité) et `AllowUsers` (liste d'users spécifique host)
  d'exampleHost **restent légitimement chez le consommateur** — ce n'est pas du
  durcissement réutilisable.
- Durcissement `arp_*` livré **mais désactivé par défaut** (`strictArp = false`) :
  arp_ignore/arp_announce peuvent casser des hôtes multi-homed / bridges docker,
  et `../nixos` fait tourner docker. Disponible à la carte, jamais forcé.
- `kernel.modules_disabled=1` (R10 strict) **non implémenté** — casse le chargement
  de modules à la demande, hors périmètre (le relic modules fait le durcissement
  *souple* : blacklist ciblée, pas le lockdown total).

---

## État constaté (analyse préalable)

Source : `../nixos/systems/x86_64-linux/exampleHost/{boot.nix,default.nix}`.

| Réglage exampleHost | Statut STC actuel | Cible 3-B |
|---|---|---|
| `net.core.bpf_jit_harden=2` | absent (`⚪` R12 dans la matrice) | `network.nix`, tag R12 → `✅` |
| `blacklistedKernelModules` (7 modules) | absent | **nouveau** `hardening/modules.nix` (R10 souple) |
| ssh `PerSourcePenalties` | absent du relic `ssh.nix` | ajouté à `ssh.nix` |
| `kptr_restrict`/`dmesg_restrict`/`unprivileged_bpf_disabled`/`perf_event_paranoid`/`yama.ptrace_scope` | **déjà dans `kernel.nix`** | rien à faire |
| `fs.file-max`, ssh `AllowUsers` | — | reste chez le consommateur |

**Rayon d'impact interne :** le nouveau relic est tiré par `cogitator/nixos/hardening.nix`.
Aucun schematic ne construit `cogitator-hardening` → aucune éval de schematic ne casse.
Le proving `provings/hardening.nix` (qui active `cogitator.hardening`) sera étendu.

---

## Décisions de conception

- **`bpf_jit_harden` → `network.nix`** : c'est un `net.core.*`, déjà classé R12
  dans `reference/anssi-bp-028.md`. Cohérent, aucune ambiguïté.
- **Nouveau relic à toggle unique** `stc.relics.hardening.modules.enable` + option
  `extraBlacklist` (liste, défaut `[]`) pour les ajouts consommateur. Pas de
  découpage firewire/réseau : KISS, `extraBlacklist` couvre les cas particuliers.
  Pas d'alias `mkRenamedOptionModule` (relic neuf, aucun namespace déprécié).
- **Wiring socle** : `cogitator.hardening` active le relic modules par défaut
  (baseline standard CIS/ANSSI ; exampleHost desktop tourne déjà avec).
- **`strictArp`** (bool, défaut `false`) dans `network.nix`, même patron que le
  `strictReversePathFilter` existant : durcissement arp disponible, jamais forcé.
- **`PerSourcePenalties`** : valeur par défaut = celle d'exampleHost
  (`crash:3600s authfail:3600s max:86400s`), réglable.

---

## Steps atomiques (une branche, 3 commits code+proving+doc)

### Step 1 — Relic module-blacklist + wiring socle
**Commit :** `feat(relics-hardening): add module blacklist relic wired into hardening suite`

Fichiers :
- `relics/nixos/hardening/modules.nix` — **nouveau**. Option
  `stc.relics.hardening.modules.{enable,extraBlacklist}` ; `config` pose
  `boot.blacklistedKernelModules = [firewire-core firewire-ohci firewire-sbp2
  dccp sctp rds tipc] ++ cfg.extraBlacklist`. Commentaires + tags `# ANSSI-BP-028 R10`.
- `relics/default.nix` — enregistrer `relics-hardening-modules = ./nixos/hardening/modules.nix;`.
- `cogitator/nixos/hardening.nix` — importer le relic, `stc.relics.hardening.modules.enable = true;`,
  mettre à jour la description du `mkEnableOption` (`… + module blacklist`) et l'en-tête.
- `provings/hardening.nix` — nouveau subtest « kernel module blacklist » : pour
  chaque module, asserter qu'il est blacklisté via la config modprobe générée
  (`modprobe --showconfig | grep 'blacklist <mod>'` ou `/etc/modprobe.d`).
- Doc (EN+FR, même commit) :
  - `docs/src/content/docs/{en,fr}/relics/hardening.md` — section `relics.hardening.modules`.
  - `docs/src/content/docs/{en,fr}/relics/index.md` — ligne de table `relics-hardening-modules`.
  - `docs/src/content/docs/{en,fr}/cogitator/hardening.md` — la suite inclut désormais le blacklist.
  - `docs/src/content/docs/{en,fr}/reference/anssi-bp-028.md` — section `relics.hardening.modules` → R10 `🟡` (blacklist ciblée, plus souple que `modules_disabled`).

### Step 2 — Absorption R12 dans le relic network
**Commit :** `feat(relics-hardening): absorb bpf_jit_harden and R12 sysctls into network relic`

Fichiers :
- `relics/nixos/hardening/network.nix` :
  - `net.core.bpf_jit_harden = 2` (tag `# ANSSI-BP-028 R12`).
  - `net.ipv4.conf.{all,default}.accept_source_route = 0` + idem `net.ipv6.conf.*` (R12).
  - `net.ipv4.tcp_rfc1337 = 1` (R12).
  - nouvelle option `strictArp` (bool, défaut `false`) ; quand `true` :
    `net.ipv4.conf.{all,default}.arp_ignore = 1` et `arp_announce = 2`. Doc de
    l'option = avertissement multi-homed/docker (calqué sur `strictReversePathFilter`).
- `provings/hardening.nix` — étendre le subtest réseau :
  `net.core.bpf_jit_harden == 2`, `net.ipv4.tcp_rfc1337 == 1`,
  `net.ipv4.conf.all.accept_source_route == 0`.
- Doc (EN+FR) :
  - `relics/hardening.md` — section network mise à jour (nouveaux sysctls + `strictArp`).
  - `reference/anssi-bp-028.md` — table network : `bpf_jit_harden` `⚪`→`✅` ;
    ajouter `accept_source_route` `✅`, `tcp_rfc1337` `✅`, `arp_*` `🟡` (via `strictArp`, opt-in).

### Step 3 — PerSourcePenalties dans le relic ssh
**Commit :** `feat(relics-hardening): add PerSourcePenalties rate-limiting to ssh relic`

Fichiers :
- `relics/nixos/hardening/ssh.nix` :
  - option `perSourcePenalties` (str, défaut `"crash:3600s authfail:3600s max:86400s"`).
  - `services.openssh.settings.PerSourcePenalties = cfg.perSourcePenalties;`.
- `provings/hardening.nix` — subtest ssh : `"persourcepenalties" in sshd_config`.
- Doc (EN+FR) : `relics/hardening.md` — section ssh mise à jour.

---

## DESIGN.md (gouvernance locale)

DESIGN.md est untracked/local (édité, **jamais commité**). Vérifier s'il énumère
les reliques hardening ; si oui, ajouter `relics.hardening.modules` **localement**
seulement. Pas de nouveau pilier (relic dans un groupe existant).

---

## Gates de validation (Phase 4, PROCEDURE_PLANS)

- [ ] `nix flake check --no-write-lock-file` vert
- [ ] Les 3 schematics évaluent (local-vm / aws-ami / dreadnought) — non impactés, sanity :
  - [ ] `nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file`
  - [ ] `nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file`
- [ ] `nix eval .#nixosModules.relics-hardening-modules` — le relic est exposé
- [ ] `just test` : proving `hardening` **vert** (nouveaux subtests inclus)
- [ ] `just ci` inchangé (proving hors gate) ; `just lint` propre (deadnix/statix sur le nouveau fichier)
- [ ] Parité doc EN/FR : `just docs-parity`
- [ ] Aucune référence de namespace périmée (Gate 3 de PROCEDURE_PLANS)
- [ ] Parité vérifiée : les reliques STC couvrent tout le durcissement d'exampleHost
      sauf `fs.file-max` + `AllowUsers` (hors périmètre, volontaire)
- [ ] 3 commits atomiques, chacun code+proving+doc, indépendamment vérifiable
