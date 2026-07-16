# Plan 3-C — Cogitator `workstation` (socle poste durci)

> Chantier C du Plan 3 de la feuille de route. Process : [PROCEDURE_PLANS.md](PROCEDURE_PLANS.md).
> Travail atomique, une branche, commits indépendamment vérifiables, doc synchronisée
> dans le même commit.
>
> **Branche :** `feat/cogitator-workstation-3c` (une PR, l'utilisateur merge/push lui-même).

---

## Objectif

Factoriser le « socle poste durci » que chaque machine perso recopie aujourd'hui
(exampleHost = plasma + gaming + yubikey + hardening) en un cogitator unique,
inspiré des postes Sécurix (poste durci ANSSI, DE par-dessus). But : un host
desktop active **une** option au lieu d'assembler la sécurité à la main.

## Contrainte de naming / architecture (décidée)

Le choix du DE est déjà isolé dans `cogitator-plasma`. Le socle `workstation`
reste **agnostique du DE**, qui est sélectionné par une **option paramétrée**
`desktop`. Ajouter un DE demain (i3) = un nouveau `cogitator-i3` + une valeur
d'enum, **le socle ne bouge pas**.

- **Décidé :** pas de `desktop = "none"` — un poste a toujours un DE ; une machine
  sans DE est un serveur, pas un workstation. L'enum démarre donc à `"plasma"`.
- **Décidé :** DE via option paramétrée (et non composition libre ni un cogitator
  par DE), pour un point d'entrée turnkey unique côté host.

## Périmètre

**STC uniquement.** La bascule d'exampleHost sur ce cogitator (et la suppression
de son hardening/ssh fait-main) fait partie du **plan de suivi consommateur**
séparé. Ce plan ne touche que le dépôt STC.

## Hors périmètre (décidé)

- **Matériel gaming** (AMD GPU + Steam) : reste `cogitator-gaming`, empilé
  séparément. Le workstation ne gère que le versant **exec filesystem** du gaming
  (Proton a besoin d'exec dans `/tmp` + `/dev/shm`), via le relic filesystem.
- `modules/home/dank-shell`, apps self-hosted, aerc : restent perso (hors STC).
- Câblage polkit/D-Bus dans le groupe `proc` (accommodation hidepid desktop) :
  **non** dans ce plan — documenté comme caveat, escape-hatch =
  `hardening.filesystem.enable = false`. Amélioration future possible.

---

## Schéma d'options (figé)

```nix
stc.cogitator.workstation = {
  enable  = true;
  desktop = "plasma";        # enum ["plasma"], défaut "plasma" (extensible "i3")
  yubikey = true;            # bool, défaut true ; false si le poste n'a pas de clé

  hardening.filesystem = {
    enable = true;           # bool, défaut true ; false si hidepid=2 gêne polkit/D-Bus
    gaming = false;          # bool, défaut false ; true → Proton peut exec (/tmp + /dev/shm)
  };
};
```

Comportement (`config`, sous `mkIf cfg.enable`) :

| Sortie | Valeur |
|---|---|
| `stc.cogitator.plasma.enable` | `cfg.desktop == "plasma"` |
| `stc.relics.hardening.kernel.enable` | `true` (socle non négociable) |
| `stc.relics.hardening.network.enable` | `true` |
| `stc.relics.hardening.modules.enable` | `true` |
| `stc.relics.hardening.filesystem.enable` | `cfg.hardening.filesystem.enable` |
| `stc.relics.hardening.filesystem.gaming` | `cfg.hardening.filesystem.gaming` |
| `stc.relics.yubikey.enable` | `cfg.yubikey` |

**Choix d'implémentation :** le cogitator importe les **relics hardening
individuels** (kernel/network/filesystem/modules — **pas ssh**) + `cogitator-plasma`
+ relic yubikey, et pose les `enable` granulairement. On **n'importe pas**
`cogitator-hardening` (dont l'`enable` unique force `filesystem = true` **et** ssh
en dur → conflit avec le passthrough `filesystem.enable = false` + on ne veut pas
sshd). Les autres options des relics (`tmpSize`, `shmSize`…) restent tunables
directement via `stc.relics.hardening.*` (convention STC).

### SSH — exclu du socle (décidé)

Le relic ssh **démarre un sshd durci** (`services.openssh.enable = true`). Décision :
**pas de sshd par défaut** sur un poste. Le workstation n'active pas le relic ssh.
Un host qui veut du SSH pose `stc.relics.hardening.ssh.enable = true` lui-même
(le relic reste importable/utilisable à la carte).

---

## Steps atomiques

### Step 1 — Cogitator `workstation` + doc (structural, 1 commit)
**Commit :** `feat(cogitator-workstation): add hardened workstation profile (DE + hardening + yubikey)`

Fichiers :
- `cogitator/nixos/workstation.nix` — **nouveau**. Options ci-dessus
  (`enable`, `desktop` enum, `yubikey` bool, `hardening.filesystem.{enable,gaming}`).
  Imports : `./plasma.nix`, les 5 relics `../../relics/nixos/hardening/*.nix`,
  `../../relics/nixos/yubikey.nix`. `config` = tableau ci-dessus.
- `cogitator/default.nix` — enregistrer `cogitator-workstation = ./nixos/workstation.nix;`.
- Doc EN+FR (même commit) :
  - `docs/src/content/docs/{en,fr}/cogitator/workstation.md` — **nouvelle page**
    bilingue (options, exemple KDE, exemple poste de jeu, note i3 futur, caveat
    hidepid/gaming).
  - `docs/src/content/docs/{en,fr}/cogitator/index.md` — ligne du nouveau cogitator.
  - `docs/src/content/docs/{en,fr}/relics/index.md` si une table « See Also »
    l'exige (à vérifier).
- DESIGN.md : gouvernance locale (untracked, jamais commité) — ajouter la ligne
  `cogitator-workstation` **localement** si DESIGN.md énumère les cogitators.

### Step 2 — Proving `workstation` (optionnel, à valider)
**Commit :** `test(provings): add workstation cogitator wiring proving`

- `provings/workstation.nix` — VM avec `stc.cogitator.workstation.enable = true`.
  Asserte le **câblage** (pas le graphique) : pcscd actif (yubikey), sysctls
  hardening effectifs (déjà couverts ailleurs mais valide la composition), unité
  `display-manager`/`sddm` présente (sans attendre `graphical.target`).
- `provings/default.nix` — wiring `legacyPackages.<sys>.provings.workstation`.
- Doc provings EN+FR : ajouter l'épreuve à la liste.
- **Gotchas connus :** le qemu-vm écrase `fileSystems` → durcissement filesystem
  (hidepid/noexec) invérifiable (cf. proving hardening). Plasma en VM =
  boot plus lourd → n'attendre que `multi-user.target`, vérifier l'existence de
  l'unité SDDM sans exiger qu'elle soit `active`.
- **Décision demandée :** inclure ce proving maintenant, ou le différer comme
  extension non bloquante (comme les provings vm/sarcophagus) ?

---

## Gates de validation (Phase 4, PROCEDURE_PLANS)

- [ ] `nix flake check --no-write-lock-file` vert
- [ ] `nix eval .#nixosModules.cogitator-workstation` — le cogitator est exposé
- [ ] Éval d'un host de test composant `workstation.enable` (kernel/yubikey/plasma
      câblés) — ou via le proving Step 2 si retenu
- [ ] Les 3 schematics évaluent (non impactés, sanity)
- [ ] `just ci` vert (fmt + lint + flake check + parité doc EN/FR)
- [ ] `just test` vert si proving ajouté
- [ ] Parité doc EN/FR : `just docs-parity` (nouvelle page présente dans les 2 langues)
- [ ] Aucune référence de namespace périmée (Gate 3 de PROCEDURE_PLANS)
- [ ] Commit(s) atomique(s), doc synchronisée dans le même commit
