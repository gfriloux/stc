# Plan v0.13.0 — Chemins critiques, chantier A : import du pool racine sans `-f`

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Refactoring Internal Code*
> (changement de défaut sur une relique existante, pas de nouvelle relique).
> Travail atomique, une branche, doc synchronisée dans le même commit.
> Chantier B ensuite : [`ssh-authorized-keys.md`](ssh-authorized-keys.md).
>
> **Branche :** `fix/zfs-force-import-root` — **Issue :** [#70](https://github.com/gfriloux/stc/issues/70)

---

## Type

Changement de défaut sur `relics/nixos/zfs.nix`. Classé **architectural** malgré
les trois lignes de code : il touche le chemin de boot de *tout* consommateur
ZFS, et il arbitre une décision de sûreté (qui a le droit d'importer un pool)
que l'issue demande explicitement d'écrire plutôt que d'hériter par accident.

## Objectif

Rendre à ZFS son garde-fou d'import : `boot.zfs.forceImportRoot` passe de `true`
inconditionnel à `lib.mkDefault false`, et le chemin d'installation est documenté
au lieu d'être rattrapé par un `-f` permanent.

## Pourquoi

`relics/nixos/zfs.nix:99-102` pose aujourd'hui :

```nix
# Force-import the root pool so the system boots even when the pool
# was last used on a different host (e.g. after nixos-anywhere install).
forceImportRoot = true;
```

Le commentaire est honnête sur le motif — et c'est précisément le problème : le
motif est **ponctuel** (le premier boot après installation), le remède est
**permanent** et s'applique à toutes les machines. Le refus d'import sur `hostid`
divergent est le mécanisme qui empêche deux hôtes de monter le même pool en
écriture et de le détruire (LUN SAN, volume cloud migré, iSCSI, disque déplacé).

Deuxième motif, nouveau depuis l'issue : **l'amont a déjà tranché dans le même
sens**. Dans le nixpkgs verrouillé, le défaut de `forceImportRoot` vaut
`lib.versionOlder config.system.stateVersion "26.11"` et le module émet un
*warning* quand ce défaut `true` s'applique. STC est du mauvais côté d'une
bascule déjà programmée.

Troisième motif, interne : le warning de `schematics/local-vm/flake.nix:81-86`
dit lui-même « *and zfs.nix forces import, which would hide the collision* ». La
relique rend inobservable le risque que le schematic prend la peine d'annoncer.

## Prémisses vérifiées (nixpkgs `4975466`, disko `725ea35`)

| Fait | Où | Conséquence |
|------|----|-------------|
| `boot.zfs.forceImportRoot` a pour défaut `lib.versionOlder config.system.stateVersion "26.11"` | `nixos/modules/tasks/filesystems/zfs.nix:355-371` | `false` devient le défaut amont à 26.11. Changer le défaut de STC, c'est précéder l'amont, pas le contredire. |
| Le module émet un warning si l'unique définition de l'option est son propre défaut à `true` | idem `:700-710` | **Supprimer** la ligne de la relique n'est pas une option : les trois schematics sont en `stateVersion = "24.11"`, donc tout consommateur hériterait `true` **et** le warning à chaque build. Il faut une définition explicite. |
| Mesuré : `bare_forceImportRoot = true` ; `bare_warnings = [ "…using the default value of `true`…" ]` | éval d'un `nixosSystem` ZFS sans STC, `stateVersion = "24.11"` | Le warning n'est pas théorique, il est reproduit. |
| Mesuré : relique actuelle → `relic_forceImportRoot = true`, `relic_warnings = [ ]` | éval avec `relics-zfs` | Le `true` explicite d'aujourd'hui *éteint* l'avertissement amont. STC masque le signal. |
| Mesuré : `mkDefault false` → valeur `false`, aucun warning ; consommateur posant `= true` (nu) → valeur `true`, aucun warning | éval des deux cas | Le remède retenu donne la valeur durcie, tait le warning (une définition existe) et laisse l'échappatoire gagner. |
| Mesuré : deux `mkDefault` concurrents (relique + consommateur) → échec d'évaluation | `tryEval` → `success = false` | Cas limite réel : un consommateur qui écrirait `lib.mkDefault true` casse l'éval. Une ligne de doc, pas de code. |
| Le scan de `/proc/cmdline` pour `zfs_force` / `zfs_force=1` / `zfs_force=y` vit dans `importLib` | `zfs.nix:89-96` | L'échappatoire par paramètre noyau existe. |
| `importLib` est injecté dans les **deux** stage-1 : `postResumeCommands` (scripté, `:740-760`) et `createImportService` (systemd, `:190`, `:800`) | idem | `zfs_force=1` marche quel que soit `boot.initrd.systemd.enable` — ce qui compte, car `relics/nixos/impermanence.nix:83` force le stage-1 systemd. |
| `8425e349` vient de `nixos/modules/profiles/base.nix:72` (`lib.mkDefault`), importé par `installer/cd-dvd/installation-cd-base.nix:15` | nixpkgs | La prémisse srvos est exacte : c'est bien le `hostId` de l'ISO d'installation. |
| Le constructeur d'image disko fait `umount -Rv "$rootMountPoint"` et **aucun `zpool export`** | `disko/lib/make-disk-image.nix:171` | Le `zpool export` de disko (`lib/types/zpool.nix:424`) n'est câblé que dans le script autonome `disko-unmount`, jamais dans le build d'image. L'état du label au premier boot est donc une question **empirique** — d'où l'étape 1 ci-dessous. |
| Les trois schematics construisent une **image** (`qcow2`, `awsImage`), aucun ne passe par `nixos-anywhere` | `schematics/*/flake.nix` en-têtes | Le motif invoqué par le commentaire de la relique (« after nixos-anywhere install ») ne décrit *aucun* chemin livré par STC. C'est une raison de plus de ne pas payer le prix en permanence. |

## Décisions

### 1. Pas de `hostId` partagé par défaut — on refuse la route srvos

srvos pose `networking.hostId = lib.mkDefault "8425e349"` pour que l'import
tombe juste sans `-f`. **STC ne le reprend pas**, trois raisons :

- Ça rouvre exactement le trou qu'on referme : deux hôtes STC avec le même
  `hostid` peuvent importer le même pool sans que ZFS n'objecte. On aurait
  déplacé la faille, pas retiré.
- Ça contredit les trois schematics, qui exigent déjà un `hostId` unique
  (`schematics/*/flake.nix` en pré-vol), et le warning de `local-vm` qui
  *vérifie* que le placeholder a été remplacé. Un défaut partagé rendrait ce
  warning absurde.
- Sémantiquement, c'est l'identité de l'ISO d'installation. Faire porter à tout
  hôte STC le `hostid` de l'installateur, c'est mentir sur qui tient le pool.

Écrit dans le commentaire du module, pas seulement ici.

### 2. `lib.mkDefault false`, pas la suppression de la ligne

Mesuré ci-dessus : supprimer la définition réveille le warning amont chez tout
consommateur en `stateVersion < 26.11`. `mkDefault false` donne la valeur sûre,
tait le warning, et laisse `boot.zfs.forceImportRoot = true;` (priorité normale)
gagner chez qui en a besoin.

### 3. Aucune option STC nouvelle

L'issue suggère « garder `forceImportRoot` comme échappatoire ». Elle l'est
déjà : c'est une option amont, d'une ligne, déjà documentée. Un
`stc.relics.zfs.forceImportRoot` serait un second nom pour la même chose — du
bruit de namespace, et une option de plus à maintenir à l'identique.

Corollaire assumé : **pas de warning STC** quand un consommateur remet `true`.
Il l'a écrit explicitement, dans son dépôt ; un avertissement sur un choix
délibéré est du bruit. L'amont ne prévient que pour le défaut, et c'est le bon
périmètre. (Divergence consciente d'avec la lecture « option 3-with-teeth » de
l'issue.)

### 4. Chemin d'installation : branche de décision pré-arbitrée

Prémisse mesurée : disko ne fait **pas** `zpool export` au build d'image, donc
on ne peut pas affirmer sur dossier qu'une image STC importe sans `-f`. Deux
issues, décidées d'avance pour que l'étape 1 soit un gate et non une surprise :

| Résultat du boot en VM avec `false` | Décision |
|---|---|
| Le pool importe, le VM boote, SSH répond | `mkDefault false` dans la relique, point. Le commentaire du module enregistre la mesure (label `hostid` compatible avec un import non forcé). |
| Le pool refuse de s'importer | Le `-f` est **structurel au chemin image**, pas à la relique : la relique garde `mkDefault false`, et les deux cogitators `sarcophagus-*` (qui *sont* le constructeur d'image) posent `boot.zfs.forceImportRoot = lib.mkDefault true` avec le commentaire qui le justifie. Le durcissement profite alors à tout hôte ZFS qui n'est pas construit en image, et le coût reste là où le problème est réel. |

Dans les deux cas la doc dit quoi faire pour une installation `nixos-anywhere`
(hors chemin STC, mais c'est le motif historique) : `zpool export <pool>` avant
le reboot, ou un boot unique avec `zfs_force=1` en paramètre noyau — mesuré
ci-dessus comme opérant dans les deux stage-1.

## Architecture

Aucune frontière DESIGN.md déplacée : la relique `stc.relics.zfs` reste la seule
propriétaire du boot ZFS. Le changement est un défaut et trois paragraphes de
doc. Si la branche « image » de la décision 4 se déclenche, les cogitators
`sarcophagus-*` reprennent une ligne qui leur appartient déjà par nature (ils
possèdent la disposition disko et la construction d'image).

## Global Constraints

- Namespace : aucune option nouvelle ; on écrit dans `boot.zfs.*`.
- Les trois schematics doivent continuer à évaluer : `local-vm`, `aws-ami`, `dreadnought`.
- Aucun secret touché.
- `provings/hardening.nix` n'assert rien sur ZFS (le module qemu-vm écrase
  `fileSystems`) : la preuve de cette issue est le boot du qcow2 `local-vm`, pas
  un proving. Écrit en toutes lettres dans le ledger pour que personne ne
  cherche un assert absent.

## Review Focus

- **Un consommateur qui ne change rien** : son prochain `nixos-rebuild` passe de
  « import forcé » à « import normal ». S'il a un pool au `hostid` divergent
  *hérité* d'une installation passée, il ne boote plus. C'est le vrai risque de
  ce chantier, et il doit être en tête de la note de release et de la doc, avec
  le remède en une ligne (`zfs_force=1`, puis `zpool export`/réimport propre).
- `boot.zfs.forceImportAll` reste `false` : vérifier que l'assertion amont
  `forceImportAll -> forceImportRoot` (`zfs.nix:678`) n'est pas violée par un
  consommateur qui aurait mis `forceImportAll = true` en comptant sur notre
  `true` implicite. Un assert amont le dira, mais le message ne nommera pas STC.
- `boot.zfs.unsafeAllowHibernation` : l'assertion amont (`:682`) l'interdit avec
  un import forcé. Passer à `false` *débloque* ce cas — effet de bord positif à
  mentionner, pas à exploiter.
- Le warning de `schematics/local-vm/flake.nix` cite la relique : s'il n'est pas
  mis à jour, il devient faux.

## Affected Files

- [ ] `relics/nixos/zfs.nix` — le défaut + le commentaire qui porte la décision
- [ ] `schematics/local-vm/flake.nix` — texte du warning `hostId`
- [ ] `docs/src/content/docs/en/relics/zfs.md` — section « Pool import »
- [ ] `docs/src/content/docs/fr/relics/zfs.md` — idem
- [ ] `.claude/plans/v0.13.0/progress.md` — ledger

## Atomic Steps

### Step 1 — Mesurer le boot avant d'écrire la ligne

**Description :** gate empirique de la décision 4. Construire l'image `local-vm`
avec `boot.zfs.forceImportRoot = false` surchargé *localement* (pas encore dans
la relique) et la booter. SSH qui répond prouve l'import : sans pool racine, il
n'y a pas de boot.

**Files changed :** aucun (surcharge temporaire, jetée après mesure).

**Verification command(s) :**
```bash
# dans schematics/local-vm, avec boot.zfs.forceImportRoot = false ajouté au module inline
just build
just run            # fenêtre QEMU, snapshot=on : l'image n'est pas modifiée
just ssh admin      # répond => le pool racine a été importé sans -f
```

**Commit message :** aucun — mesure, consignée au ledger.

---

### Step 2 — Le défaut

**Description :** `forceImportRoot = lib.mkDefault false` dans la relique, et le
commentaire réécrit pour porter les décisions 1 à 4 (pourquoi pas de `hostId`
partagé, pourquoi `mkDefault` et pas suppression, où est l'échappatoire). Si la
branche « image » s'est déclenchée à l'étape 1, les deux `sarcophagus-*` prennent
leur ligne dans le même commit.

**Files changed :** `relics/nixos/zfs.nix` (+ `cogitator/nixos/sarcophagus-{kvm,aws}.nix` selon étape 1)

**Interfaces :**
- Consomme : rien.
- Produit : `boot.zfs.forceImportRoot = false` (priorité 1000), surchargeable par une définition nue.

**Verification command(s) :**
```bash
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.boot.zfs.forceImportRoot --no-write-lock-file   # false
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.warnings --no-write-lock-file                   # pas de ligne forceImportRoot
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.boot.zfs.forceImportRoot --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.boot.zfs.forceImportRoot --no-write-lock-file
```
(les trois premières commandes sont mesurées sur l'arbre actuel : `true`, deux
warnings sans rapport, `true`.)

**Commit message :** `fix(zfs): stop forcing the root pool import by default`

---

### Step 3 — Le warning du schematic

**Description :** `schematics/local-vm/flake.nix` dit « *and zfs.nix forces
import, which would hide the collision* ». Ce n'est plus vrai : la collision
*sera* visible, c'est tout l'objet du chantier. Reformuler.

**Files changed :** `schematics/local-vm/flake.nix`

**Verification command(s) :**
```bash
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.warnings --no-write-lock-file
grep -n "forces import" schematics/local-vm/flake.nix   # doit ne rien rendre
```

**Commit message :** `docs(local-vm): the hostId warning no longer claims the import is forced`

---

### Step 4 — Doc EN + FR

**Description :** récrire la section « Pool import » : ce qui est protégé, ce qui
est échangé, les deux échappatoires (`forceImportRoot = true` ; `zfs_force=1`
pour un boot unique), le piège du double `mkDefault` mesuré, et la note
d'installation `nixos-anywhere` (`zpool export` avant reboot). Mentionner que
`false` deviendra le défaut amont à 26.11.

**Files changed :** `docs/src/content/docs/{en,fr}/relics/zfs.md`

**Verification command(s) :**
```bash
just docs-parity
grep -n "forceImportRoot" docs/src/content/docs/en/relics/zfs.md docs/src/content/docs/fr/relics/zfs.md
```

**Commit message :** `docs(zfs): document what the root-pool import guard protects`

## Quality Gates

- [ ] `just ci` (fmt-check + lint + `nix flake check` + docs-parity)
- [ ] `nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file`
- [ ] `nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file`
- [ ] `nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file`
- [ ] Boot réel du qcow2 `local-vm` reproduit après le commit (pas seulement à l'étape 1)
- [ ] `just test` — les provings ne couvrent pas ZFS, mais rien ne doit régresser
- [ ] Ledger à jour : résultat de l'étape 1, branche de la décision 4 retenue
